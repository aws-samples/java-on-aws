package com.unicorn.core;

import software.amazon.awscdk.services.lambda.IFunction;

public class ThreadDumpAlarmProps {
    private final IFunction lambdaFunction;

    private ThreadDumpAlarmProps(Builder builder) {
        this.lambdaFunction = builder.lambdaFunction;
    }

    public IFunction getLambdaFunction() {
        return lambdaFunction;
    }

    public static Builder builder() {
        return new Builder();
    }

    public static class Builder {
        private IFunction lambdaFunction;

        public Builder lambdaFunction(IFunction function) {
            this.lambdaFunction = function;
            return this;
        }

        public ThreadDumpAlarmProps build() {
            if (lambdaFunction == null) {
                throw new IllegalStateException("Lambda function must be specified");
            }
            return new ThreadDumpAlarmProps(this);
        }
    }
}
