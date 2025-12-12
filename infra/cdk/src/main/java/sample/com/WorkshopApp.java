package sample.com;

import software.amazon.awscdk.App;
import software.amazon.awscdk.StackProps;
import sample.com.stacks.WorkshopStack;

public class WorkshopApp {
    public static void main(final String[] args) {
        App app = new App();

        new WorkshopStack(app, "WorkshopStack", StackProps.builder()
            .build());

        app.synth();
    }
}