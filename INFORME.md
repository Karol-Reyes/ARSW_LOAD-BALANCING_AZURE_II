# Escalamiento en Azure con Functions (Serverless)

## 1. Objetivo y escenario de calidad

Evaluar cómo se comporta una aplicación serverless en Azure Functions que calcula el enésimo número de la secuencia de Fibonacci, frente al siguiente escenario de calidad:

```
Escalabilidad:
Cuando un conjunto de usuarios consulta un enésimo número (superior a 1.000.000) de la secuencia de Fibonacci de forma concurrente y el sistema se encuentra bajo condiciones normales de operación, todas las peticiones deben ser respondidas y el consumo de CPU del sistema no puede superar el 70 %.
```

Se miden dos cosas por separado: 

1. Que todas las peticiones sean respondidas
2. Que la CPU no supere el 70 %.

## 2. Entorno

| Elemento | Valor |
|---|---|
| Function App | `FunctionFibonacci` |
| Grupo de recursos | `SCALABILITY_LAB_II` |
| Región | East US 2 |
| Suscripción | Azure for Students |
| Sistema operativo | Windows |
| Plan de tarifa | Dinámico (plan Consumption) |
| Versión del runtime de Functions | 4.x (4.1054.250.26428 en el portal) |
| Lenguaje | JavaScript (Node.js), librería `big-integer` |
| Funciones | `Fibonacci` (iterativa) y `FibonacciMemo` (recursiva con memoization), ambas con HTTP trigger |

La función `Fibonacci` recibe `{"nth": N}` por POST y calcula el resultado con un ciclo que suma números grandes (`big-integer`). Con N = 1.000.000 el resultado tiene unos 209.000 dígitos (209 kB de respuesta).

## 3. Despliegue y problemas encontrados

Durante el despliegue desde Visual Studio Code aparecieron tres problemas, resueltos así:

| Problema | Causa | Solución |
|---|---|---|
| `func` no se reconoce como comando | No estaba instalado Azure Functions Core Tools | Instalar Core Tools y reabrir VS Code |
| Aviso: la versión remota `~4` no coincide con la local `~2` | `azureFunctions.projectRuntime` quedó en `~2` en `.vscode/settings.json` | Cambiarlo a `~4` |
| Error de arranque en el portal: el extension bundle 1.8.1 no cumple la versión mínima requerida (2.6.1) | `host.json` referenciaba un bundle antiguo | Actualizar el rango de `extensionBundle` a `[4.*, 5.0.0)` |

Tras corregirlos, la función respondió correctamente desde **Código y prueba** en el portal (para `{"nth": 10}` devolvió 55).

## 4. Pruebas de carga con Newman

### 4.1 Método

- Se creó una colección de Postman con una petición POST a la función con `{"nth": 1000000}`.
- Newman ejecuta las iteraciones una detrás de otra, así que para lograr concurrencia se lanzaron N procesos de Newman en paralelo con PowerShell, mediante el script `prueba-concurrente.ps1` incluido en el repositorio.
- El script guarda un JSON por petición y un `resumen.csv` en la carpeta indicada.

```powershell
.\prueba-concurrente.ps1 -Concurrent 10
.\prueba-concurrente.ps1 -Concurrent 20 -OutDir resultados_20
.\prueba-concurrente.ps1 -Concurrent 100 -OutDir resultados_100
```

### 4.2 Resultados

| Prueba | Respondidas (200 OK) | Promedio | Mínimo | Máximo | Duración total |
|---|---|---|---|---|---|
| 1 petición (línea base) | 1 de 1 | 10,2 s | 10,2 s | 10,2 s | 10,2 s |
| 10 concurrentes | 10 de 10 | 63,8 s | 9,6 s | 73,9 s | 76,3 s |
| 20 concurrentes | 20 de 20 | 24,9 s | 8,3 s | 36,0 s | 67,8 s |
| 100 concurrentes | 100 de 100 | 153,7 s | 7,5 s | 216,8 s | 479,0 s |

![](</images/Captura de pantalla 2026-11-04 185552.png>)

![](</images/Captura de pantalla 2026-11-04 191308.png>)

![](</images/Captura de pantalla 2026-11-04 192221.png>)

### 4.3 Análisis

- **Disponibilidad.** En todas las pruebas respondieron todas las peticiones con 200 OK; no hubo errores ni timeouts. La parte "todas las peticiones deben ser respondidas" del escenario se cumple.

- **Latencia.** Una petición sola tarda unos 10 s. Con concurrencia el tiempo crece mucho: con 100 peticiones el promedio fue de 153,7 s y la más lenta de 216,8 s. La mayoría de las peticiones se agrupan en tiempos largos, y solo unas pocas salen cerca del tiempo de una petición aislada, lo que es consistente con peticiones que esperan en cola.

- **Causa probable.** El cálculo es un ciclo de CPU puro en Node.js, que ejecuta en un solo hilo por instancia: mientras una instancia calcula, las demás peticiones esperan. Esto es una interpretación a partir de los datos, no algo medido directamente.

- **Orden de las pruebas.** La prueba de 20 salió mejor (promedio 24,9 s) que la de 10 (63,8 s). Una explicación posible es que la prueba de 10 corrió con la aplicación más "fría" y que luego Azure tenía más capacidad disponible.

- **Limitación de la medición.** Los 100 procesos de Newman se lanzaron desde un solo computador personal. La duración total de la prueba de 100 (479 s) es mucho mayor que la petición más lenta (216,8 s), lo que sugiere que parte del tiempo se perdió lanzando y gestionando los procesos localmente. Los tiempos individuales de respuesta pueden incluir ese efecto.

## 5. Métricas en Azure

### 5.1 Azure Monitor (Métricas de la Function App)

![](</images/Captura de pantalla 2026-11-04 192033.png>)

![](</images/Captura de pantalla 2026-11-04 192522.png>)

- *Function Execution Units* muestra picos que coinciden con las horas de las pruebas, el más alto con la prueba de 100 peticiones (suma de 2,09 B en la ventana mostrada).

- *Function Execution Count* sumó 134 ejecuciones en la ventana, compatible con las pruebas lanzadas más las ejecuciones manuales desde el portal.

- *Automatic Scaling Instance Count* salió sin datos (`--`), por lo que **esta métrica no permite afirmar cuántas instancias creó Azure**.

- *Response Time* promedio de Azure Monitor (9,08 s y 39,46 s en dos momentos distintos) no coincide con los tiempos de Newman. Probablemente se debe a que Azure promedia sobre toda la ventana, incluyendo periodos sin carga. Para el análisis se usan los tiempos medidos por Newman.

### 5.2 Application Insights

![](</images/Captura de pantalla 2026-11-04 192801.png>)

![](</images/Captura de pantalla 2026-11-04 192821.png>)

![](</images/Captura de pantalla 2026-11-04 192836.png>)

- *Solicitudes de servidor*: 146 en la ventana, con un pico de unas 90 que corresponde a la prueba de 100 peticiones.

- *Tiempo de respuesta del servidor*: promedio de 1,89 min en la ventana, con un pico de entre 2,5 y 3 min coherente con lo medido por Newman.

- *Solicitudes con errores*: 2, ocurridas antes de iniciar las pruebas de carga (cuando la aplicación aún presentaba el error de arranque). Durante las pruebas de carga no hubo fallos.

### 5.3 Live Metrics (CPU)

![](</images/Captura de pantalla 2026-11-04 193057.png>)

![](</images/Captura de pantalla 2026-11-04 193128.png>)

- *CPU Total (%)* llegó a cerca del **100 %** mientras llegaban las peticiones y bajó a casi 0 al terminar.

- *Request Failure Rate* y *Exception Rate* se mantuvieron en 0.

- La memoria comprometida se mantuvo estable (alrededor de 450 MB), por lo que el cuello de botella es la CPU y no la memoria.

## 6. Función con memoization (recursiva)

### 6.1 Implementación

Se creó la función `FibonacciMemo`: una versión recursiva que guarda en un `Map` en memoria (a nivel de proceso) los resultados ya calculados. En cada respuesta devuelve `cacheHit` (si el valor ya estaba calculado), `tamanoCache` (cantidad de entradas guardadas), `ms` (tiempo de cálculo) e `instancia` (identificador de la instancia que respondió).

![](</images/Captura de pantalla 2026-11-04 193925.png>)

### 6.2 Resultados

| Momento | Prueba | cacheHit | tamanoCache | ms |
|---|---|---|---|---|
| Ronda 1 | `nth = 1000` (1.ª vez) | false | 1001 | 1 |
| Ronda 1 | `nth = 1000` (2.ª vez) | true | 1001 | 0 |
| Ronda 1 | `nth = 3000` (1.ª vez) | false | 3001 | 7 |
| Ronda 1 | `nth = 3000` (2.ª vez) | true | 3001 | 0 |
| 7:49 p. m. (unos 4 min después) | `nth = 3000` | true | 3001 | 0 |
| 8:04 p. m. (15 min sin llamadas) | `nth = 1000` y `nth = 3000` | true | 3001 | 0 |
| 8:07 p. m. (3 min después) | `nth = 1500` | **false** | **1501** | 1 |
| 8:07 p. m. | `nth = 3500` | false | 3501 | 1 |

![](</images/Captura de pantalla 2026-11-04 194035.png>)

![](</images/Captura de pantalla 2026-11-04 194104.png>)

![](</images/Captura de pantalla 2026-11-04 194120.png>)

![](</images/Captura de pantalla 2026-11-04 194140.png>)

![](</images/Captura de pantalla 2026-11-04 194515.png>)

![](</images/Captura de pantalla 2026-11-04 194915.png>)

![](</images/Captura de pantalla 2026-11-04 200442.png>)

![](</images/Captura de pantalla 2026-11-04 200716.png>)

![](</images/Captura de pantalla 2026-11-04 200729.png>)

### 6.3 Comportamiento observado

- Mientras el proceso sigue vivo, la memoization funciona: cada valor se calcula una vez y después se responde desde la memoria (`cacheHit: true`, 0 ms). Como la recursión guarda los valores intermedios, calcular 3000 deja guardados también todos los valores menores (por eso `tamanoCache` es 3001).

- Tras 15 minutos sin llamadas el caché seguía vivo. A las 8:07 p. m., 3 minutos después, el caché estaba vacío: pedir `nth = 1500`, que debía estar ya guardado, dio `cacheHit: false` con `tamanoCache = 1501`, es decir, se recalculó desde cero.

- **Conclusión del experimento:** el caché en memoria no desaparece en un plazo fijo ni predecible; sobrevivió 15 minutos y se perdió poco después sin que se reiniciara nada manualmente. No se puede confiar en él.

- El identificador de `instancia` fue el mismo antes y después de la pérdida del caché, por lo que no sirve para detectar el reciclaje: lo que se perdió fue la memoria del proceso, no la máquina. El indicador útil es `cacheHit` junto con `tamanoCache`.

## 7. Preguntas

### ¿Qué es un Azure Function?

Es el servicio de cómputo serverless de Azure para ejecutar fragmentos de código en respuesta a eventos, sin administrar servidores. Cada función se activa mediante un *trigger* (una petición HTTP, un temporizador, un mensaje en una cola, un archivo nuevo en un blob, etc.) y puede leer y escribir datos mediante *bindings*. 

Varias funciones se agrupan en una **Function App**, que es la unidad que se despliega y escala. En este laboratorio ambas funciones usan un trigger HTTP.

### ¿Qué es serverless?

Es un modelo de ejecución en el que el proveedor administra los servidores, el escalamiento y la infraestructura, y el desarrollador solo entrega el código. 

Los servidores existen, pero no se gestionan. Sus características principales son escalamiento automático según la demanda, cobro por uso (en los planes de consumo) y la posibilidad de escalar a cero cuando no hay carga. 

A cambio, el código debe ser **sin estado** y se aceptan limitaciones como el arranque en frío (*cold start*) y los límites de tiempo por ejecución. Lo que se vio en el laboratorio sobre el caché en memoria es una consecuencia directa de esto.

### ¿Qué es el runtime y qué implica seleccionarlo al crear la Function App?

Hay dos cosas que se suelen llamar "runtime":

- **El runtime (host) de Azure Functions**, identificado por su versión mayor (en este laboratorio, la 4.x). Es el motor que recibe los eventos y ejecuta las funciones.
- **El runtime stack**, es decir, el lenguaje y su versión (Node.js, .NET, Python, Java, etc.), que se elige al crear la Function App.

Esa elección implica qué lenguaje debe tener el código desplegado, qué versiones del lenguaje se soportan, qué sistemas operativos están disponibles y qué versión del host se usa. 

Elegirlo mal o dejar el proyecto con una versión distinta a la de la app genera errores, como los que ocurrieron en este laboratorio: el proyecto local estaba configurado con `~2` mientras la app remota usaba `~4`, y el `extensionBundle` del `host.json` era demasiado antiguo para el runtime 4.

### ¿Por qué es necesario crear un Storage Account junto con una Function App?

Porque el runtime de Functions usa una cuenta de almacenamiento para su funcionamiento interno. Según la documentación de Azure, la usa para guardar el código y la configuración de la app en el plan Consumption y Premium, mantener las claves de las funciones y el estado de los bindings (Blob), manejar reintentos y control de algunos triggers (colas), coordinar el escalamiento y registrar la ejecución de las funciones. 

Si se elimina la cuenta de almacenamiento, la Function App deja de funcionar. Además, la cuenta se factura aparte y no es la misma cosa que el almacenamiento que use la lógica de la aplicación.

### ¿Cuáles son los tipos de planes de una Function App? ¿En qué se diferencian?

Las opciones de alojamiento actuales son las siguientes:

| Plan | Cobro | Escala a cero | Tiempo máximo por ejecución | Ventajas | Desventajas |
|---|---|---|---|---|---|
| **Consumption** | Por uso real (GB-s y ejecuciones), con cuota gratuita mensual | Sí | 5 min por defecto, 10 como máximo | Muy económico para cargas bajas o esporádicas; escalamiento automático; sin costo si no se usa | Arranque en frío; tiempo de ejecución limitado; sin integración con redes virtuales; marcado como heredado |
| **Flex Consumption** | Por uso, más opción de instancias siempre listas | Sí | 30 min por defecto, sin límite máximo | Escalamiento rápido; integración con redes virtuales; instancias *always ready* para reducir el arranque en frío; recomendado para apps nuevas | Solo Linux; una app por plan; cuota de memoria por región y suscripción |
| **Premium** | Por vCPU y memoria de las instancias asignadas, con al menos una siempre activa | No | 30 min por defecto, sin límite máximo | Sin arranque en frío (instancias precalentadas); redes virtuales; tiempos largos; Windows y Linux | Costo fijo aunque no haya tráfico; más caro que los planes de consumo para cargas bajas |
| **Dedicated (App Service)** | Como cualquier recurso de App Service (por instancia, todo el tiempo) | No | 30 min por defecto, sin límite máximo | Costo predecible; permite aprovechar capacidad de App Service ya contratada | Se paga siempre; no está pensado para escalar automáticamente por eventos al ritmo de los planes serverless |
| **Container Apps** | Según Azure Container Apps | Según configuración | 30 min por defecto | Permite ejecutar Functions en contenedores Linux | Mayor complejidad de operación |

### ¿Por qué la memoization falla o no funciona de forma correcta?

Con los resultados de la sección 6, las causas son:

1. **El caché vive en la memoria de un proceso.** En un entorno serverless la plataforma puede reciclar o reiniciar ese proceso en cualquier momento, y la memoria se pierde.

2. **Cada instancia tiene su propio caché.** Si Azure escala a varias instancias, una petición puede caer en una instancia donde el valor no está guardado, aunque otra instancia ya lo haya calculado. Las instancias no comparten memoria.

3. **Las funciones deben ser sin estado.** Guardar datos en variables globales va contra ese modelo, y el comportamiento resultante no es predecible.

4. **Arranque en frío.** Tras un periodo sin tráfico, la siguiente petición puede ejecutarse en un proceso nuevo, con el caché vacío.

5. **La recursión tiene un límite de profundidad.** Para valores de N muy grandes se espera un desbordamiento de pila (no se verificó en el laboratorio).

### ¿Cómo funciona el sistema de facturación de las Function App?

Depende del plan:

- **Consumption.** Se cobra por **consumo de recursos observado**, medido en gigabytes-segundo (GB-s), es decir, memoria usada (en GB) multiplicada por el tiempo de ejecución (en segundos), más el número de ejecuciones. Cada ejecución se factura con un mínimo de 100 ms y 128 MB.

- **Flex Consumption.** Se cobra por uso bajo demanda (GB-s y ejecuciones) con una cuota gratuita menor (100.000 GB-s y 250.000 ejecuciones al mes), más un cargo base si se configuran instancias *always ready*.
- **Premium.** Se cobra por los vCPU-segundo y GB-segundo de las instancias asignadas, sin cargo por ejecución, y siempre hay al menos una instancia activa.
- **Dedicated.** Se paga la tarifa del plan de App Service mientras exista, independientemente del número de ejecuciones.

Aparte de lo anterior, la cuenta de almacenamiento y Application Insights se facturan por separado.