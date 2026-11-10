# Planificador Personal

Aplicación nativa para macOS hecha con SwiftUI. Incluye dashboard diario, agenda, vista semanal, tareas, metas con hitos, finanzas en MXN, categorías editables con emoji, cuentas con saldo inicial, presupuestos por semana, mes o periodo personalizado, avisos y dos widgets de macOS.

Las tareas y los eventos admiten varios avisos personalizables en minutos, horas, días o semanas. Ambos pueden añadirse al Calendario de macOS. Las categorías se pueden crear, editar, archivar y restaurar; al archivarlas, los movimientos anteriores conservan su categoría.

Las tareas, compromisos, metas e hitos admiten etiquetas. El dashboard agrupa pendientes por etiqueta, permite filtrarlos y muestra los vencidos. Al cerrar una actividad se registra la fecha de cierre y puedes corregirla en su editor. La app compara ese cierre con la fecha límite: **antes de tiempo** si fue en un día anterior, **a tiempo** si fue el mismo día y antes de la hora límite, y **con atraso** si fue después. Para compromisos y tareas hay un margen de un minuto para no clasificar como atraso el instante en que marcas el cierre. Los registros completados en versiones anteriores quedan sin clasificación hasta que les asignes su fecha real de cierre.

## Finanzas

El dashboard financiero muestra **patrimonio total = disponible + cajas**, flujo de ingresos y gastos de seis meses, gastos por categoría, presupuestos e historial de movimientos y transferencias. El dinero disponible es el que está fuera de las cajas. Puedes fijar cuánto tienes **hoy**; la app ajusta el saldo base sin borrar movimientos anteriores. También puedes editar el saldo actual de cada caja de la misma forma.

Al registrar un ingreso o gasto eliges el espacio de origen o destino. Un gasto desde una caja se descuenta de ella directamente. Las transferencias permiten mover dinero entre disponible y cajas o entre dos cajas; no cuentan como ingreso ni gasto y no cambian el patrimonio total.

## Abrir en VS Code

Abre esta carpeta en VS Code. El código de la app está en `Sources/Planificador`; el widget está en `Sources/PlanificadorWidget`.

## Crear la app

En la terminal de VS Code:

```sh
zsh Scripts/build-app.sh
```

El resultado se guarda en `dist/Planificador-Personal-macOS.zip`. Descomprímelo y mueve **Planificador Personal.app** a Aplicaciones. Si ya tienes una versión anterior, ciérrala antes de reemplazarla. Tus datos siguen en `~/Library/Application Support/Planificador/planner.json`. Para poner un widget, abre la galería de widgets de macOS y busca **Planificador Personal**; hay versiones **Mi día** y **Próximos pasos** en tres tamaños.

Esta compilación usa las herramientas de línea de comandos de Swift y firma local. Para distribuirla a otros Macs o publicarla se necesita firma de Apple y Xcode. Los widgets comparten datos mediante el grupo `group.com.planificador.personal`; si macOS no registra el widget de una compilación local, Xcode y una firma de desarrollo son el siguiente paso.

## Datos y permisos

Los datos se guardan en `~/Library/Application Support/Planificador/planner.json`. Los avisos y el Calendario se activan desde Ajustes. Los eventos se añaden al calendario predeterminado de macOS al marcar **Añadir al Calendario**; iCloud funciona si la cuenta ya está configurada en Calendario. La app no lee el correo.


## Finanzas 0.5

Finanzas se organiza en tres pestañas: **Dashboard**, **Movimientos** y **Cajas y deudas**. Cada caja, tarjeta y préstamo tiene una ficha y un historial. Las tarjetas permiten definir límite de crédito, próxima fecha de pago y notas; los préstamos y otras deudas también tienen nombre y saldo editable.

En un movimiento de gasto elige **Contado**, **Compra a crédito** o **Abono a deuda**. Una compra a crédito aumenta la deuda seleccionada y cuenta como gasto de su categoría sin descontar efectivo. Un abono descuenta del disponible o de una caja y reduce la deuda; los reportes y presupuestos lo separan para no duplicar el gasto de la compra. La categoría Deudas abre la selección de deuda; puedes marcar otras categorías para abonos desde su editor. Los saldos negativos de deuda representan saldo a favor. Los intereses y comisiones se registran como cargos; no se calculan automáticamente.

En **Movimientos → Pagos fijos** guarda servicios y suscripciones con importe, frecuencia y próximo vencimiento. Aparecen también en el dashboard. **Registrar pago** prepara un movimiento editable; **Próxima fecha** avanza el vencimiento del catálogo. Registrar el gasto y actualizar la fecha son acciones independientes. El catálogo no realiza cargos automáticos ni envía notificaciones del sistema.

Los archivos anteriores se leen con sus registros conservados. Los datos de prueba se mantienen fuera del archivo personal.

## Finanzas 0.6 y navegación

- **Barra lateral colapsable**: usa el botón de menú tipo sándwich (`☰`) o el atajo `⌘\` para ocultar o mostrar la barra lateral.
- **Apartado mensual de pagos fijos**: calcula automáticamente cuánto debes apartar cada mes sumando cobros semanales, quincenales, mensuales y el prorrateo de pagos bimestrales, trimestrales, semestrales, anuales o únicos según los meses restantes hasta su próximo vencimiento. Al avanzar al siguiente cobro (`Siguiente cobro`), recalcula sobre el ciclo completo (por ejemplo, 12 meses para pagos anuales).
- **Alta y edición renovada de pagos fijos**: vista previa en vivo del impacto mensual, cuadrícula visual de frecuencias y categorías, y sugerencias rápidas.
- **Tarjetas en Cajas y deudas**: muestra directamente en la tarjeta el **monto disponible**, el monto usado, el límite y el porcentaje ocupado.
- **Filtros en Movimientos**: filtra tu actividad por periodo (`Todo`, `Hoy`, `Esta semana`, `Por mes` o `Rango de fechas`), tipo de movimiento, categorías (una o varias) y búsqueda por texto, con suma en vivo de ingresos y gastos filtrados.
- **Instalación directa**: `zsh Scripts/build-app.sh` genera el archivo en `dist/` y actualiza automáticamente `/Applications/Planificador Personal.app` lista para anclar al Dock.
