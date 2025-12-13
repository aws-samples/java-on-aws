package sample.com.constructs;

import software.amazon.awscdk.services.iam.*;
import software.constructs.Construct;
import org.json.JSONObject;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

public class Roles extends Construct {

    public Roles(final Construct scope, final String id) {
        super(scope, id);

        // Custom unicorn roles will be added here in future tasks
    }

}