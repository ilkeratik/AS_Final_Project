FROM mcr.microsoft.com/dotnet/sdk:9.0-alpine AS build

WORKDIR /src
COPY . .

# Build custom plugins into Presentation/Nop.Web/Plugins before publishing the web app.
# This makes federation features image-native instead of relying on runtime file copies.
RUN dotnet build /src/Plugins/Nop.Plugin.Federation.Outbox/Nop.Plugin.Federation.Outbox.csproj -c Release -p:SolutionDir=/src/
RUN dotnet build /src/Plugins/Nop.Plugin.ExternalAuth.Keycloak/Nop.Plugin.ExternalAuth.Keycloak.csproj -c Release -p:SolutionDir=/src/
RUN mkdir -p /src/Presentation/Nop.Web/Plugins/ExternalAuth.Keycloak/Views \
    && cp /src/Plugins/Nop.Plugin.ExternalAuth.Keycloak/plugin.json /src/Presentation/Nop.Web/Plugins/ExternalAuth.Keycloak/plugin.json \
    && cp /src/Plugins/Nop.Plugin.ExternalAuth.Keycloak/Views/PublicInfo.cshtml /src/Presentation/Nop.Web/Plugins/ExternalAuth.Keycloak/Views/PublicInfo.cshtml \
    && cp /src/Plugins/Nop.Plugin.ExternalAuth.Keycloak/Views/_ViewImports.cshtml /src/Presentation/Nop.Web/Plugins/ExternalAuth.Keycloak/Views/_ViewImports.cshtml

WORKDIR /src/Presentation/Nop.Web
RUN dotnet publish Nop.Web.csproj -c Release -o /app/publish -p:SolutionDir=/src/

FROM mcr.microsoft.com/dotnet/aspnet:9.0-alpine

RUN apk add --no-cache icu-libs gcompat tzdata libgdiplus libc6-compat
ENV ASPNETCORE_URLS=http://+:80 \
    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false

WORKDIR /app
COPY --from=build /app/publish .

# Copy required App_Data subdirectories that may not be included in publish
COPY --from=build /src/Presentation/Nop.Web/App_Data/Localization ./App_Data/Localization
COPY --from=build /src/Presentation/Nop.Web/App_Data/Installation ./App_Data/Installation
COPY --from=build /src/Presentation/Nop.Web/App_Data/Gmail ./App_Data/Gmail

EXPOSE 80
ENTRYPOINT ["dotnet", "Nop.Web.dll"]

