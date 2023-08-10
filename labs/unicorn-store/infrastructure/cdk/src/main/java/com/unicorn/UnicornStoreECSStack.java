package com.unicorn;

import com.unicorn.constructs.UnicornStoreECS;
import com.unicorn.core.InfrastructureStack;
import software.amazon.awscdk.*;
import software.constructs.Construct;

public class UnicornStoreECSStack extends Stack {

    public UnicornStoreECSStack(final Construct scope, final String id, final StackProps props,
            final InfrastructureStack infrastructureStack, final String projectName) {
        super(scope, id, props);

        new UnicornStoreECS(this, id, infrastructureStack, projectName);
    }
}
