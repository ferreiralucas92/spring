# Estágio para resolver e baixar dependências.
FROM eclipse-temurin:11-jdk-jammy as deps

WORKDIR /build

# Copiar o wrapper mvnw com permissões executáveis.
COPY --chmod=0755 mvnw mvnw
COPY .mvn/ .mvn/

# Baixar dependências em um passo separado para aproveitar o cache do Docker.
RUN --mount=type=bind,source=pom.xml,target=pom.xml \
    --mount=type=cache,target=/root/.m2 ./mvnw dependency:go-offline -DskipTests

################################################################################

# Estágio para construir a aplicação.
FROM deps as package

WORKDIR /build

COPY ./src src/
RUN --mount=type=bind,source=pom.xml,target=pom.xml \
    --mount=type=cache,target=/root/.m2 \
    ./mvnw package -DskipTests && \
    mv target/$(./mvnw help:evaluate -Dexpression=project.artifactId -q -DforceStdout)-$(./mvnw help:evaluate -Dexpression=project.version -q -DforceStdout).jar target/app.jar

################################################################################

# Extrair a aplicação em camadas para melhor cacheamento.
FROM package as extract

WORKDIR /build

RUN java -Djarmode=layertools -jar target/app.jar extract --destination target/extracted

################################################################################

# Estágio final para rodar a aplicação com dependências mínimas.
FROM eclipse-temurin:11-jre-jammy AS final

ARG UID=10001
RUN adduser \
    --disabled-password \
    --gecos "" \
    --home "/nonexistent" \
    --shell "/sbin/nologin" \
    --no-create-home \
    --uid "${UID}" \
    appuser
USER appuser

# Copiar os arquivos extraídos do estágio anterior.
COPY --from=extract build/target/extracted/dependencies/ ./
COPY --from=extract build/target/extracted/spring-boot-loader/ ./
COPY --from=extract build/target/extracted/snapshot-dependencies/ ./
COPY --from=extract build/target/extracted/application/ ./

EXPOSE 8080

ENTRYPOINT ["java", "org.springframework.boot.loader.JarLauncher"]
