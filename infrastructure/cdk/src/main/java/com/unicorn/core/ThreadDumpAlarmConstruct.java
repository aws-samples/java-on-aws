package com.unicorn.core;

import software.amazon.awscdk.Duration;
import software.amazon.awscdk.services.cloudwatch.Alarm;
import software.amazon.awscdk.services.cloudwatch.ComparisonOperator;
import software.amazon.awscdk.services.cloudwatch.Metric;
import software.amazon.awscdk.services.cloudwatch.TreatMissingData;
import software.amazon.awscdk.services.cloudwatch.actions.LambdaAction;
import software.constructs.Construct;

import java.util.Map;

public class ThreadDumpAlarmConstruct extends Construct {

    private final Alarm threadCountAlarm;

    public ThreadDumpAlarmConstruct(final Construct scope, final String id, ThreadDumpAlarmProps props) {
        super(scope, id);

        // Create metric for thread count
        Metric threadCountMetric = Metric.Builder.create()
                .namespace("ApplicationSignals")
                .metricName("JVMThreadCount")
                .dimensionsMap(Map.of(
                        "Environment", "eks:unicorn-store/unicorn-store",
                        "Service", "unicorn-store"
                ))
                .period(Duration.seconds(60))
                .statistic("Average")
                .build();

        // Create the alarm
        this.threadCountAlarm = Alarm.Builder.create(this, "ThreadCountAlarm")
                .alarmName("JVMThreadCount")
                .metric(threadCountMetric)
                .threshold(100)
                .evaluationPeriods(1)
                .datapointsToAlarm(1)
                .comparisonOperator(ComparisonOperator.GREATER_THAN_THRESHOLD)
                .treatMissingData(TreatMissingData.BREACHING)
                .actionsEnabled(true)
                .build();

        // Add Lambda action
        threadCountAlarm.addAlarmAction(new LambdaAction(props.getLambdaFunction()));
    }

    public Alarm getAlarm() {
        return threadCountAlarm;
    }
}