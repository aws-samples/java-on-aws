docker run --rm  --network host -p 5432:5432 -e POSTGRES_DB=unicorns -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres --name postgres postgres:13.11
