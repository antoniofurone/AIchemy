## Build immagine Flink (DOCKER)
docker build -t antoniofurone/flink-docker:latest .
## Push dell'immagione su DockerHub
docker push antoniofurone/flink-docker:latest

## Deploy session cluster (DOCKER)
kubectl apply -f flink-docker.yml

## Verifica
kubectl -n flink get pods
kubectl -n flink get flinkdeployment

## UI
kubectl -n flink port-forward svc/beam-flink-cluster-rest 8081:8081

## Cleanup
kubectl delete -f flink-docker.yml

