package com.unicorn;

import com.unicorn.constructs.UnicornStoreEKS;
import com.unicorn.core.InfrastructureStack;
import software.amazon.awscdk.*;
import software.constructs.Construct;

public class UnicornStoreEKSStack extends Stack {
    public UnicornStoreEKSStack(final Construct scope, final String id, final StackProps props,
            final InfrastructureStack infrastructureStack, final String projectName) {
        super(scope, id, props);

        new UnicornStoreEKS(this, id, infrastructureStack, projectName);
    }
}
