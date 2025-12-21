import urllib3
from trino.dbapi import connect
from trino.auth import BasicAuthentication

# Disabilita warning SSL per certificati self-signed
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# https
conn = connect(
    host='34.14.90.97',
    port=8443,
    user='admin',
    http_scheme='https',
    auth=BasicAuthentication('admin', 'admin123'),
    catalog='iceberg',
    schema='default',
    verify=False
)


# Crea schema se non esiste
cur = conn.cursor()


try:

    # iceberg.ic_test
    print("\n=== Schemi nel catalogo iceberg (prima) ===")
    cur.execute('SHOW SCHEMAS')
    rows = cur.fetchall()
    for row in rows:
        print(row)

    cur.execute('CREATE SCHEMA IF NOT EXISTS iceberg.ic_test')
    print("Schema iceberg.ic_test creato o già esistente")

    # Crea tabella se non esiste
    cur.execute('''
        CREATE TABLE IF NOT EXISTS iceberg.ic_test.orders (
            order_id INTEGER,
            customer_id INTEGER,
            order_date DATE,
            amount DECIMAL(10,2)
        )
    ''')
    print("Tabella iceberg.ic_test.orders creata o già esistente")

    # Inserisci dati solo se order_id non esiste
    orders_to_insert = [
        (1, 101, '2025-01-15', 99.99),
        (2, 102, '2025-01-16', 149.50)
    ]
    
    for order_id, customer_id, order_date, amount in orders_to_insert:
        # Verifica se order_id esiste già
        cur.execute(f'SELECT COUNT(*) FROM iceberg.ic_test.orders WHERE order_id = {order_id}')
        count = cur.fetchone()[0]
        
        if count == 0:
            cur.execute(f'''
                INSERT INTO iceberg.ic_test.orders 
                VALUES ({order_id}, {customer_id}, DATE '{order_date}', {amount})
            ''')
            print(f"Inserito order_id {order_id}")
        else:
            print(f"Order_id {order_id} già esistente, skip inserimento")

    # Visualizza il contenuto della tabella orders
    print("\nContenuto tabella iceberg.ic_test.orders:")
    cur.execute('SELECT * FROM iceberg.ic_test.orders ORDER BY order_id')
    orders = cur.fetchall()
    if orders:
        print(f"{'order_id':<10} {'customer_id':<12} {'order_date':<12} {'amount':<10}")
        print("-" * 50)
        for order in orders:
            print(f"{order[0]:<10} {order[1]:<12} {order[2]!s:<12} {order[3]:<10}")
    else:
        print("Nessun dato presente nella tabella")

    print("\n=== Schemi nel catalogo iceberg (dopo) ===")
    cur.execute('SHOW SCHEMAS')
    rows = cur.fetchall()
    for row in rows:
        print(row)

    # end iceberg.ic_test
    # lance.ln_test
    
    # Visualizza schemi nel catalogo lance
    print("\n=== Schemi nel catalogo lance (prima) ===")
    cur.execute('SHOW SCHEMAS IN lance')
    lance_schemas = cur.fetchall()
    for schema in lance_schemas:
        print(schema)

    # Crea schema ln_test in lance
    cur.execute('CREATE SCHEMA IF NOT EXISTS lance.ln_test')
    print("Schema lance.ln_test creato o già esistente")

    # Crea tabella embeddings
    cur.execute('''
        CREATE TABLE IF NOT EXISTS lance.ln_test.embeddings (
            id INTEGER,
            document_name VARCHAR,
            content VARCHAR,
            embedding ARRAY(DOUBLE),
            metadata MAP(VARCHAR, VARCHAR),
            created_at TIMESTAMP
        )
    ''')
    print("Tabella lance.ln_test.embeddings creata o già esistente")

    # Inserisci dati solo se id non esiste
    embeddings_to_insert = [
        (1, 'doc1.txt', 'Sample text about AI', 
         [0.1, 0.2, 0.3, 0.4, 0.5],
         {'category': 'tech', 'language': 'en'}),
        (2, 'doc2.txt', 'Machine learning basics',
         [0.2, 0.3, 0.1, 0.5, 0.4],
         {'category': 'tech', 'language': 'en'}),
        (3, 'doc3.txt', 'Deep learning concepts',
         [0.15, 0.25, 0.2, 0.45, 0.42],
         {'category': 'ai', 'language': 'en'})
    ]
    
    for emb_id, doc_name, content, embedding, metadata in embeddings_to_insert:
        # Verifica se id esiste già
        cur.execute(f'SELECT COUNT(*) FROM lance.ln_test.embeddings WHERE id = {emb_id}')
        count = cur.fetchone()[0]
        
        if count == 0:
            # Converti lista in formato ARRAY e dict in MAP
            embedding_str = 'ARRAY[' + ','.join(map(str, embedding)) + ']'
            metadata_keys = list(metadata.keys())
            metadata_values = list(metadata.values())
            metadata_str = f"MAP(ARRAY{metadata_keys}, ARRAY{metadata_values})"
            
            cur.execute(f'''
                INSERT INTO lance.ln_test.embeddings 
                VALUES ({emb_id}, '{doc_name}', '{content}', {embedding_str}, {metadata_str}, CURRENT_TIMESTAMP)
            ''')
            print(f"Inserito embedding id {emb_id}")
        else:
            print(f"Embedding id {emb_id} già esistente, skip inserimento")

    # Visualizza il contenuto della tabella embeddings
    print("\nContenuto tabella lance.ln_test.embeddings:")
    cur.execute('SELECT id, document_name, content FROM lance.ln_test.embeddings ORDER BY id')
    embeddings = cur.fetchall()
    if embeddings:
        print(f"{'id':<5} {'document_name':<15} {'content':<30}")
        print("-" * 55)
        for emb in embeddings:
            print(f"{emb[0]:<5} {emb[1]:<15} {emb[2]:<30}")
    else:
        print("Nessun dato presente nella tabella")

    # Calcola dot product tra embedding id=1 e id=2
    print("\n=== Calcolo similitudine (dot product) tra embedding 1 e 2 ===")
    dot_product_query = '''
    WITH vec1 AS (
        SELECT embedding as v1 
        FROM lance.ln_test.embeddings 
        WHERE id = 1
    ),
    vec2 AS (
        SELECT embedding as v2 
        FROM lance.ln_test.embeddings 
        WHERE id = 2
    )
    SELECT 
        REDUCE(
            TRANSFORM(
                SEQUENCE(1, CARDINALITY(v1)),
                i -> v1[i] * v2[i]
            ),
            0.0,
            (s, x) -> s + x,
            s -> s
        ) as dot_product
    FROM vec1, vec2
    '''
    cur.execute(dot_product_query)
    result = cur.fetchone()
    if result:
        print(f"Dot product tra embedding 1 e 2: {result[0]}")
    else:
        print("Nessun risultato")

    # Visualizza schemi nel catalogo lance
    print("\n=== Schemi nel catalogo lance (dopo) ===")
    cur.execute('SHOW SCHEMAS IN lance')
    lance_schemas = cur.fetchall()
    for schema in lance_schemas:
        print(schema)

except Exception as e:
    print(f"Errore: {e}")



cur.close()
conn.close()