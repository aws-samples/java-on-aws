package sample.com.constructs;

import software.amazon.awscdk.services.ec2.*;
import software.constructs.Construct;
import java.util.List;

public class Vpc extends Construct {
    private final IVpc vpc;

    public Vpc(final Construct scope, final String id) {
        super(scope, id);

        this.vpc = software.amazon.awscdk.services.ec2.Vpc.Builder.create(this, "WorkshopVpc")
            .vpcName("workshop-vpc")
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
    }

    public IVpc getVpc() {
        return vpc;
    }
}