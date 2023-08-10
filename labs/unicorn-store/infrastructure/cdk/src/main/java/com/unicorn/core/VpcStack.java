package com.unicorn.core;

import software.amazon.awscdk.*;
import software.amazon.awscdk.services.ec2.*;
import software.constructs.Construct;

public class VpcStack extends Stack {

    private final IVpc vpc;

    public VpcStack(final Construct scope, final String id, final StackProps props) {
        super(scope, id, props);

        vpc = createUnicornVpc();
        new CfnOutput(this, "idUnicornStoreVPC", CfnOutputProps.builder()
                .value(vpc.getVpcId())
                .build());
        Tags.of(vpc).add("unicorn", "true");
        new CfnOutput(this, "arnUnicornStoreVPC", CfnOutputProps.builder()
                .value(vpc.getVpcArn())
                .build());
        new CfnOutput(this, "idUnicornStoreVPCPublicSubnet1", CfnOutputProps.builder()
                .value(vpc.getPublicSubnets().get(0).getSubnetId())
                .exportName("idUnicornStoreVPCPublicSubnet1")
                .build());
        new CfnOutput(this, "idUnicornStoreVPCPublicSubnet2", CfnOutputProps.builder()
                .value(vpc.getPublicSubnets().get(1).getSubnetId())
                .exportName("idUnicornStoreVPCPublicSubnet2")
                .build());
        new CfnOutput(this, "idUnicornStoreVPCPrivateSubnet1", CfnOutputProps.builder()
                .value(vpc.getPrivateSubnets().get(0).getSubnetId())
                .exportName("idUnicornStoreVPCPrivateSubnet1")
                .build());
        new CfnOutput(this, "idUnicornStoreVPCPrivateSubnet2", CfnOutputProps.builder()
                .value(vpc.getPrivateSubnets().get(1).getSubnetId())
                .exportName("idUnicornStoreVPCPrivateSubnet2")
                .build());
    }

    private IVpc createUnicornVpc() {
        return Vpc.Builder.create(this, "UnicornVpc")
                .vpcName("UnicornVPC")
                .build();
    }

    public IVpc getVpc() {
        return vpc;
    }
}
