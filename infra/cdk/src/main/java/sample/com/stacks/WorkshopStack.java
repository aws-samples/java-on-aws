package sample.com.stacks;

import software.amazon.awscdk.Stack;
import software.amazon.awscdk.StackProps;
import software.amazon.awscdk.CfnOutput;
import software.amazon.awscdk.Aws;
import software.constructs.Construct;
import sample.com.constructs.*;
import java.util.Map;

public class WorkshopStack extends Stack {
    public WorkshopStack(final Construct scope, final String id, final StackProps props) {
        super(scope, id, props);

        String workshopType = System.getenv("WORKSHOP_TYPE");
        if (workshopType == null) {
            workshopType = "ide"; // default
        }

        // Core infrastructure (always created)
        Roles roles = new Roles(this, "Roles");
        Vpc vpc = new Vpc(this, "Vpc");
        Ide ide = new Ide(this, "Ide", vpc.getVpc(), roles);

        // CodeBuild for workshop setup
        CodeBuild codeBuild = new CodeBuild(this, "CodeBuild", vpc.getVpc(), roles,
            Map.of("STACK_NAME", Aws.STACK_NAME, "WORKSHOP_TYPE", workshopType));

        // TODO: Add conditional resources in subsequent tasks
        // - EKS cluster (for non-ide, non-java-ai-agents workshops)
        // - Database (for non-ide workshops)

        // Output the workshop type for verification
        CfnOutput.Builder.create(this, "WorkshopType")
            .value(workshopType)
            .description("The type of workshop being deployed")
            .build();
    }
}