# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------
# Build stage
# ---------------------------------------------------------------------------
FROM maven:3.9.16-eclipse-temurin-21-alpine AS build

WORKDIR /build

# Copy only dependency descriptors first to maximize Docker layer caching.
COPY pom.xml ./

# Download dependencies using BuildKit's persistent Maven cache.
RUN --mount=type=cache,target=/root/.m2 \
    mvn -B -DskipTests dependency:go-offline

# Copy source only after dependencies have been cached.
COPY src ./src

# Build the application.
RUN --mount=type=cache,target=/root/.m2 \
    mvn -B -DskipTests clean package

# ---------------------------------------------------------------------------
# Runtime stage
# ---------------------------------------------------------------------------
FROM eclipse-temurin:21-jre-alpine

ARG APPINSIGHTS_AGENT_VERSION=3.7.9

ENV APPINSIGHTS_AGENT_VERSION="${APPINSIGHTS_AGENT_VERSION}" \
    APPINSIGHTS_AGENT_SHA256="4ab7a442bf9defc7475d026c6b49042793ebb010c391a1db91ae07da0c04d848"

WORKDIR /app

# curl is needed for the agent download and container health check.
RUN apk add --no-cache curl \
    && mkdir -p /opt/appinsights

# Download the Application Insights Java agent and verify its checksum.
RUN set -eux; \
    agent_url="https://github.com/microsoft/ApplicationInsights-Java/releases/download/${APPINSIGHTS_AGENT_VERSION}/applicationinsights-agent-${APPINSIGHTS_AGENT_VERSION}.jar"; \
    curl \
        --fail \
        --silent \
        --show-error \
        --location \
        --retry 5 \
        --retry-delay 2 \
        --retry-all-errors \
        --connect-timeout 30 \
        --max-time 300 \
        --output /opt/appinsights/applicationinsights-agent.jar \
        "${agent_url}"; \
    printf '%s  %s\n' \
        "${APPINSIGHTS_AGENT_SHA256}" \
        /opt/appinsights/applicationinsights-agent.jar \
        | sha256sum -c -; \
    test -s /opt/appinsights/applicationinsights-agent.jar

# Copy the application artifact from the build stage.
COPY --from=build /build/target/*.jar /app/app.jar

# Create a dedicated non-root user.
RUN addgroup -S appgroup \
    && adduser -S -D -H -G appgroup appuser \
    && chown -R appuser:appgroup /app /opt/appinsights

USER appuser

EXPOSE 8080

# Spring Boot actuator health endpoint.
HEALTHCHECK --interval=30s \
    --timeout=5s \
    --start-period=60s \
    --retries=3 \
    CMD curl --fail --silent --show-error \
        http://127.0.0.1:8080/actuator/health \
        >/dev/null || exit 1

# Microsoft documents the exec-form Java agent configuration for containers.
ENTRYPOINT ["java", "-javaagent:/opt/appinsights/applicationinsights-agent.jar", "-jar", "/app/app.jar"]
