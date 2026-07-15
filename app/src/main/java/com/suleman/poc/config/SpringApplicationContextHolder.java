package com.suleman.poc.config;

import com.suleman.poc.Application;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.WebApplicationType;
import org.springframework.context.ApplicationContext;

public class SpringApplicationContextHolder {

    private static ApplicationContext context;

    public static synchronized ApplicationContext get() {
        if (context == null) {
            try {
                SpringApplication app = new SpringApplication(Application.class);
                context = app.run();
            } catch (Exception e) {
                context = null;
                throw e;
            }
        }
        return context;
    }

    public static synchronized void set(ApplicationContext ctx) {
        context = ctx;
    }
}
