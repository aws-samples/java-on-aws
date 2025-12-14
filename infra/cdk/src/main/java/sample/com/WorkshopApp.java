package sample.com;

import software.amazon.awscdk.App;
import software.amazon.awscdk.AppProps;
import software.amazon.awscdk.StackProps;
import software.amazon.awscdk.DefaultStackSynthesizer;
import software.amazon.awscdk.DefaultStackSynthesizerProps;

public class WorkshopApp {
    public static void main(final String[] args) {
        App app = new App(AppProps.builder()
            .analyticsReporting(false)
            .build());

        new WorkshopStack(app, "WorkshopStack", StackProps.builder()
            .synthesizer(new DefaultStackSynthesizer(DefaultStackSynthesizerProps.builder()
                .generateBootstrapVersionRule(false) // This disables the bootstrap version parameter
                .build()))
            .build());

        app.synth();
    }
}