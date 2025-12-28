## Build immagine Flink (PROCESS)
docker build -t antoniofurone/flink-proc:latest .
docker push antoniofurone/flink-proc:latest

## Deploy session cluster (PROC)
kubectl apply -f flink-proc.yml

## Verifica
kubectl -n flink get pods
kubectl -n flink get flinkdeployment

## UI
kubectl -n flink port-forward svc/beam-flink-cluster-rest 8081:8081

## Cleanup
kubectl delete -f flink-proc.yml