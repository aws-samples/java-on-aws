package sample.com.constructs;

import io.github.cdklabs.cdknag.NagPackSuppression;
import io.github.cdklabs.cdknag.NagSuppressions;
import software.amazon.awscdk.Aws;
import software.amazon.awscdk.CustomResource;
import software.amazon.awscdk.Duration;
import software.amazon.awscdk.RemovalPolicy;
import software.amazon.awscdk.services.cloudfront.AllowedMethods;
import software.amazon.awscdk.services.cloudfront.BehaviorOptions;
import software.amazon.awscdk.services.cloudfront.CachePolicy;
import software.amazon.awscdk.services.cloudfront.Distribution;
import software.amazon.awscdk.services.cloudfront.ViewerProtocolPolicy;
import software.amazon.awscdk.services.cloudfront.origins.S3BucketOrigin;
import software.amazon.awscdk.services.iam.Effect;
import software.amazon.awscdk.services.iam.ManagedPolicy;
import software.amazon.awscdk.services.iam.PolicyStatement;
import software.amazon.awscdk.services.iam.Role;
import software.amazon.awscdk.services.iam.ServicePrincipal;
import software.amazon.awscdk.services.s3.BlockPublicAccess;
import software.amazon.awscdk.services.s3.Bucket;
import software.amazon.awscdk.services.s3.BucketEncryption;
import software.amazon.awscdk.services.ssm.StringParameter;
import software.constructs.Construct;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import java.util.stream.Stream;

/**
 * Corporate travel portal of the agentcore-ai-agents workshop: a static site (flights, hotels,
 * booking form, the deals page with the hidden prompt injection) on S3 behind CloudFront (OAC).
 * The pages (apps/agentcore-ai-agents/travel-portal) are written to the bucket by a custom resource,
 * so the template needs no CDK asset bucket. SSM parameter {prefix}-portal-url holds the site's URL.
 */
public class TravelPortal extends Construct {

    /** The portal pages in the workshop code (cdk synth runs in infra/cdk). */
    private static final Path SOURCE = Path.of("..", "..", "apps", "agentcore-ai-agents", "travel-portal");
    private static final Map<String, String> CONTENT_TYPES = Map.of(
        "html", "text/html; charset=utf-8",
        "css", "text/css; charset=utf-8",
        "js", "application/javascript; charset=utf-8",
        "json", "application/json",
        "svg", "image/svg+xml",
        "txt", "text/plain; charset=utf-8");

    private final Bucket bucket;
    private final Distribution distribution;

    public static class TravelPortalProps {
        private String prefix = "workshop";

        public static TravelPortalProps.Builder builder() { return new Builder(); }

        public static class Builder {
            private final TravelPortalProps props = new TravelPortalProps();

            public Builder prefix(String prefix) { props.prefix = prefix; return this; }
            public TravelPortalProps build() { return props; }
        }

        public String getPrefix() { return prefix; }
    }

    public TravelPortal(final Construct scope, final String id, final TravelPortalProps props) {
        super(scope, id);
        String prefix = props.getPrefix();

        // Emptied by CfnPreDeleteCleanup before the stack deletes it
        this.bucket = Bucket.Builder.create(this, "Bucket")
            .bucketName(prefix + "-portal-" + Aws.ACCOUNT_ID + "-" + Aws.REGION)
            .blockPublicAccess(BlockPublicAccess.BLOCK_ALL)
            .encryption(BucketEncryption.S3_MANAGED)
            .enforceSsl(true)
            .removalPolicy(RemovalPolicy.DESTROY)
            .build();

        this.distribution = Distribution.Builder.create(this, "Distribution")
            .comment("Corporate travel portal")
            .defaultRootObject("index.html")
            .defaultBehavior(BehaviorOptions.builder()
                .origin(S3BucketOrigin.withOriginAccessControl(bucket))
                .viewerProtocolPolicy(ViewerProtocolPolicy.REDIRECT_TO_HTTPS)
                .cachePolicy(CachePolicy.CACHING_OPTIMIZED)
                .allowedMethods(AllowedMethods.ALLOW_GET_HEAD)
                .compress(true)
                .build())
            .build();

        Role deployRole = Role.Builder.create(this, "DeployRole")
            .assumedBy(ServicePrincipal.Builder.create("lambda.amazonaws.com").build())
            .managedPolicies(List.of(
                ManagedPolicy.fromAwsManagedPolicyName("service-role/AWSLambdaBasicExecutionRole")))
            .build();
        deployRole.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of("s3:ListBucket"))
            .resources(List.of(bucket.getBucketArn()))
            .build());
        deployRole.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of("s3:PutObject", "s3:DeleteObject"))
            .resources(List.of(bucket.arnForObjects("*")))
            .build());
        deployRole.addToPolicy(PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of("cloudfront:CreateInvalidation"))
            .resources(List.of("arn:aws:cloudfront::" + Aws.ACCOUNT_ID + ":distribution/" + distribution.getDistributionId()))
            .build());

        var deployFunction = new Lambda(this, "Deploy",
            "/lambda/static-site-deploy.py", prefix + "-portal-deploy", Duration.minutes(2), deployRole);

        var deployment = CustomResource.Builder.create(this, "Pages")
            .serviceToken(deployFunction.getFunction().getFunctionArn())
            .properties(Map.of(
                "BucketName", bucket.getBucketName(),
                "DistributionId", distribution.getDistributionId(),
                "Files", loadPages()))
            .build();
        deployment.getNode().addDependency(deployRole);

        StringParameter.Builder.create(this, "UrlParameter")
            .parameterName(prefix + "-portal-url")
            .description("Corporate travel portal URL (agentcore-ai-agents workshop)")
            .stringValue("https://" + distribution.getDistributionDomainName())
            .build();

        NagSuppressions.addResourceSuppressions(bucket, List.of(
            NagPackSuppression.builder().id("AwsSolutions-S1")
                .reason("Static workshop site; access logs are not needed").build()), true);
    }

    /** Pages under apps/agentcore-ai-agents/travel-portal as [{Key, ContentType, Body}]. */
    private List<Map<String, String>> loadPages() {
        Path root = SOURCE;
        if (!Files.isDirectory(root)) {
            throw new IllegalStateException("Travel portal folder not found: " + root.toAbsolutePath());
        }
        try (Stream<Path> paths = Files.walk(root)) {
            return paths.filter(Files::isRegularFile).sorted().map(path -> {
                String key = root.relativize(path).toString().replace('\\', '/');
                String extension = key.substring(key.lastIndexOf('.') + 1);
                String contentType = CONTENT_TYPES.get(extension);
                if (contentType == null) {
                    throw new IllegalStateException("Unsupported travel portal file (text files only): " + key);
                }
                try {
                    return Map.of("Key", key, "ContentType", contentType, "Body", Files.readString(path));
                } catch (IOException e) {
                    throw new UncheckedIOException(e);
                }
            }).toList();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    public Bucket getBucket() {
        return bucket;
    }

    public Distribution getDistribution() {
        return distribution;
    }
}
