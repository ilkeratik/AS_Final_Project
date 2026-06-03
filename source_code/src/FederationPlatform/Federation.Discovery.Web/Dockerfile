FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src
COPY ["FederationPlatform/Federation.Discovery.Web/Federation.Discovery.Web.csproj", "FederationPlatform/Federation.Discovery.Web/"]
RUN dotnet restore "FederationPlatform/Federation.Discovery.Web/Federation.Discovery.Web.csproj"
COPY FederationPlatform/Federation.Discovery.Web/ FederationPlatform/Federation.Discovery.Web/
WORKDIR "/src/FederationPlatform/Federation.Discovery.Web"
RUN dotnet publish -c Release -o /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:9.0
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/* \
    && adduser --disabled-password --gecos "" appuser
WORKDIR /app
COPY --from=build /app/publish .
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=5s --start-period=15s --retries=6 \
  CMD curl -fs http://localhost:8080/health || exit 1
USER appuser
ENTRYPOINT ["dotnet", "Federation.Discovery.Web.dll"]



