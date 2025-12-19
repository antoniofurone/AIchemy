from trino.dbapi import connect
from trino.auth import BasicAuthentication

# https
conn = connect(
    host='localhost',
    port=8443,
    user='admin',
    http_scheme='https',
    auth=BasicAuthentication('admin', 'admin123'),
    catalog='iceberg',
    schema='default',
    verify=False
)


# Esegui una query
cur = conn.cursor()
cur.execute('SHOW SCHEMAS')
rows = cur.fetchall()
for row in rows:
    print(row)

cur.close()
conn.close()