# Deploy del Job (DOCKER)
## Build dell'immagine
docker build -t antoniofurone/beam-flink-hello:latest .
## Push dell'immagione su DockerHub
docker push antoniofurone/beam-flink-hello:latest

Possibili alternative rispetto a DockerHub sono:
- Registry Privato su Kubernetes - utilizzando un immagine specifica
- GitHub Container Registry
- Google Container Registry (GCR)
...

## Creazione namespace se non esiste
kubectl create namespace flink

## Deploy su K8s
kubectl apply -f hello.yml

## Verifica lo stato

### 1. Verifica Flink Session Cluster
```bash
kubectl get flinkdeployment -n flink
kubectl get pods -n flink
```

Aspetta che JobManager e TaskManager siano Running.

### 2. Verifica Job Python Pod
```bash
kubectl get pod beam-python-job -n flink
kubectl logs -n flink beam-python-job -f
```

### 3. Accedi alla Flink UI
```bash
kubectl port-forward -n flink svc/beam-flink-session-rest 8081:8081
```
Apri http://localhost:8081

## Cleanup
```bash
kubectl delete -f hello.yml
```

## Note
- Il cluster Flink gira in **session mode** (senza job embedded)
- Il pod `beam-python-job` sottomette il job Python Beam al cluster
- Se il pod fallisce, controlla i log e riavvialo: `kubectl delete pod beam-python-job -n flink`