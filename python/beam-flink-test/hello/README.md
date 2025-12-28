# Deploy del Job (PROCESS)

## Build immagine del job (se necessaria)
docker build -t antoniofurone/beam-flink-hello:latest .
docker push antoniofurone/beam-flink-hello:latest

## Deploy su K8s (PROC)
kubectl apply -f hello.yml

## Verifica
kubectl -n flink get pods
kubectl -n flink logs -f beam-python-job-proc

## Cleanup
kubectl delete -f hello.yml