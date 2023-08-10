package com.unicorn;

import com.unicorn.core.VpcStack;
import io.github.cdklabs.cdknag.AwsSolutionsChecks;
import io.github.cdklabs.cdknag.NagPackSuppression;
import io.github.cdklabs.cdknag.NagSuppressions;
import software.amazon.awscdk.App;
import software.amazon.awscdk.Aspects;
import software.amazon.awscdk.StackProps;

import java.util.List;

public class UnicornStoreVpcStack {

    public static void main(final String[] args) {
        App app = new App();

        var vpcStack = new VpcStack(app, "UnicornStoreVpc", StackProps.builder().build());

        //Add CDK-NAG checks: https://github.com/cdklabs/cdk-nag
        //Add suppression to exclude certain findings that are not needed for Workshop environment
        Aspects.of(app).add(new AwsSolutionsChecks());
        var suppressionVpc = List.of(
            new NagPackSuppression.Builder().id("AwsSolutions-VPC7").reason("Workshop environment does not need VPC flow logs").build()
        );
        NagSuppressions.addStackSuppressions(vpcStack, suppressionVpc);

        app.synth();
    }
}
