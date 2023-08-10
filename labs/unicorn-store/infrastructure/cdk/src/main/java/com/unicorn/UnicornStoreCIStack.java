package com.unicorn;

import com.unicorn.constructs.UnicornStoreCI;
import com.unicorn.core.InfrastructureStack;
import software.amazon.awscdk.*;
import software.constructs.Construct;

public class UnicornStoreCIStack extends Stack {

    public UnicornStoreCIStack(final Construct scope, final String id, final StackProps props,
            final InfrastructureStack infrastructureStack, final String projectName) {
        super(scope, id, props);

        new UnicornStoreCI(this, id, infrastructureStack, projectName);
    }
}
