package com.suleman.poc;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.SQSEvent;
import com.suleman.poc.adapters.messaging.DeliveryConsumer;
import com.suleman.poc.adapters.messaging.InvoiceConsumer;
import com.suleman.poc.adapters.messaging.NotificationConsumer;
import com.suleman.poc.config.SpringApplicationContextHolder;
import org.springframework.context.ApplicationContext;

public class SqsLambdaHandler implements RequestHandler<SQSEvent, Void> {

    @Override
    public Void handleRequest(SQSEvent event, Context context) {
        ApplicationContext springContext = SpringApplicationContextHolder.get();

        if (event.getRecords() == null) {
            context.getLogger().log("No records found in SQS event.");
            return null;
        }

        for (SQSEvent.SQSMessage msg : event.getRecords()) {
            String queueArn = msg.getEventSourceArn();
            String body = msg.getBody();

            context.getLogger().log("Received SQS Event Source ARN: " + queueArn);

            if (queueArn == null) {
                context.getLogger().log("Queue ARN is null, unable to route message.");
            } else if (queueArn.contains("notification")) {
                springContext.getBean(NotificationConsumer.class).handleOrderPlaced(body);
            } else if (queueArn.contains("invoice")) {
                springContext.getBean(InvoiceConsumer.class).handleOrderPlaced(body);
            } else if (queueArn.contains("delivery")) {
                springContext.getBean(DeliveryConsumer.class).handleOrderPlaced(body);
            } else {
                context.getLogger().log("Unknown SQS Event Source Queue: " + queueArn);
            }
        }
        return null;
    }
}
