FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src
COPY ["FederationPlatform/Federation.MeilisearchIndexer/Federation.MeilisearchIndexer.csproj", "FederationPlatform/Federation.MeilisearchIndexer/"]
COPY ["FederationPlatform/Federation.Contracts/Federation.Contracts.csproj",                   "FederationPlatform/Federation.Contracts/"]
RUN dotnet restore "FederationPlatform/Federation.MeilisearchIndexer/Federation.MeilisearchIndexer.csproj"
COPY . .
WORKDIR "/src/FederationPlatform/Federation.MeilisearchIndexer"
RUN dotnet publish -c Release -o /app/publish

FROM mcr.microsoft.com/dotnet/runtime:9.0
RUN adduser --disabled-password --gecos "" appuser
WORKDIR /app
COPY --from=build /app/publish .
USER appuser
ENTRYPOINT ["dotnet", "Federation.MeilisearchIndexer.dll"]



