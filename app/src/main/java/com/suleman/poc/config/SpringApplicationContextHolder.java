package com.suleman.poc.config;

import com.suleman.poc.Application;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.WebApplicationType;
import org.springframework.context.ApplicationContext;

public class SpringApplicationContextHolder {

    private static ApplicationContext context;

    public static synchronized ApplicationContext get() {
        if (context == null) {
            SpringApplication app = new SpringApplication(Application.class);
            app.setWebApplicationType(WebApplicationType.NONE);
            context = app.run();
        }
        return context;
    }

    public static synchronized void set(ApplicationContext ctx) {
        context = ctx;
    }
}
