# syntax=docker/dockerfile:1
# ─── Build ────────────────────────────────────────────────────────────────────
FROM gradle:8.10-jdk21-alpine AS build
WORKDIR /app
COPY gradlew settings.gradle.kts build.gradle.kts ./
COPY gradle ./gradle
# Dependências em camada própria: só invalida se os arquivos de build mudarem
RUN --mount=type=cache,target=/root/.gradle \
    gradle dependencies --no-daemon > /dev/null
# Código-fonte: mudanças aqui não invalidam a camada acima
COPY src ./src
RUN --mount=type=cache,target=/root/.gradle \
    gradle bootJar --no-daemon -x test

# ─── Runtime ──────────────────────────────────────────────────────────────────
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

RUN apk add --no-cache curl
RUN addgroup -S app && adduser -S -G app app \
    && chown app:app /app

COPY --from=build --chown=app:app /app/build/libs/service-portal-admin.jar app.jar

ENV SBA_USERNAME=admin \
    SBA_PASSWORD=admin

ENV SERVER_PORT=8080 \
    SPRING_PROFILES_ACTIVE="" \
    JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"

EXPOSE 8080

USER app

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar app.jar"]
