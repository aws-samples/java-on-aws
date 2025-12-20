package sample.com.constructs;

import software.amazon.awscdk.services.ec2.*;
import software.amazon.awscdk.services.ssm.StringParameter;
import software.constructs.Construct;
import java.util.List;

public class Vpc extends Construct {
    private final IVpc vpc;

    public static class VpcProps {
        private String prefix = "workshop";

        public static VpcProps.Builder builder() { return new Builder(); }

        public static class Builder {
            private VpcProps props = new VpcProps();

            public Builder prefix(String prefix) { props.prefix = prefix; return this; }
            public VpcProps build() { return props; }
        }

        public String getPrefix() { return prefix; }
    }

    public Vpc(final Construct scope, final String id) {
        this(scope, id, VpcProps.builder().build());
    }

    public Vpc(final Construct scope, final String id, final VpcProps props) {
        super(scope, id);

        String prefix = props.getPrefix();

        this.vpc = software.amazon.awscdk.services.ec2.Vpc.Builder.create(this, "Vpc")
            .vpcName(prefix + "-vpc")
            .ipAddresses(IpAddresses.cidr("10.0.0.0/16"))
            .enableDnsSupport(true)
            .enableDnsHostnames(true)
            .maxAzs(2)
            .natGateways(1)
            .subnetConfiguration(List.of(
                SubnetConfiguration.builder()
                    .name("Public")
                    .subnetType(SubnetType.PUBLIC)
                    .cidrMask(24)
                    .build(),
                SubnetConfiguration.builder()
                    .name("Private")
                    .subnetType(SubnetType.PRIVATE_WITH_EGRESS)
                    .cidrMask(24)
                    .build()
            ))
            .build();

        // Store VPC ID in SSM Parameter for cross-stack reference
        StringParameter.Builder.create(this, "VpcIdParameter")
            .parameterName(prefix + "-vpc-id")
            .description("Workshop VPC ID for cross-stack reference")
            .stringValue(this.vpc.getVpcId())
            .build();
    }

    public IVpc getVpc() {
        return vpc;
    }
}