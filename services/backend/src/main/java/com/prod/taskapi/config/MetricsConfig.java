package com.prod.taskapi.config;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Central definition of application business metrics.
 *
 * <p>The Spring-managed MeterRegistry is used so the meters participate in the
 * application's configured Micrometer/Actuator registry. With Application
 * Insights Java 3.x autocollection enabled, Micrometer and Spring Boot Actuator
 * metrics are collected by the Application Insights agent.
 *
 * <p>Metric names intentionally retain the existing dashboard contract.
 */
@Configuration(proxyBeanMethods = false)
public class MetricsConfig {

  @Bean
  public Counter taskCreatedCounter(MeterRegistry registry) {
    return Counter.builder("task_created_total")
        .description("Total number of tasks created")
        .register(registry);
  }

  @Bean
  public Timer taskCreationTimer(MeterRegistry registry) {
    return Timer.builder("task_creation_duration")
        .description("Time spent persisting a newly created task")
        .register(registry);
  }

  @Bean
  public Timer taskFetchTimer(MeterRegistry registry) {
    return Timer.builder("task_fetch_duration")
        .description("Time spent fetching tasks for a user")
        .register(registry);
  }

  @Bean
  public Counter authSuccessCounter(MeterRegistry registry) {
    return Counter.builder("auth_success_total")
        .description("Total number of successful registration or login operations")
        .register(registry);
  }

  @Bean
  public Counter authFailureCounter(MeterRegistry registry) {
    return Counter.builder("auth_failure_total")
        .description("Total number of failed registration or login operations")
        .register(registry);
  }
}