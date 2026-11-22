"""Muestra ligera de CPU y RAM del kernel Linux."""


def mostrar_bytes(tamanio):
    valor = float(tamanio)
    for unidad in ("B", "KiB", "MiB", "GiB", "TiB"):
        if valor < 1024 or unidad == "TiB":
            return f"{tamanio} B" if unidad == "B" else f"{valor:.1f} {unidad}"
        valor /= 1024


def rendimiento():
    with open("/proc/stat", encoding="ascii") as archivo:
        cpu = [int(valor) for valor in archivo.readline().split()[1:9]]
    memoria = {}
    with open("/proc/meminfo", encoding="ascii") as archivo:
        for linea in archivo:
            clave, _, valor = linea.partition(":")
            if clave in ("MemTotal", "MemAvailable"):
                memoria[clave] = int(valor.split()[0]) * 1024
                if len(memoria) == 2:
                    break
    total = memoria["MemTotal"]
    usada = max(0, total - memoria["MemAvailable"])
    return {"ticks": sum(cpu), "inactivos": cpu[3] + cpu[4],
            "ram": round(100 * usada / total), "usoRam": mostrar_bytes(usada),
            "totalRam": mostrar_bytes(total)}


if __name__ == "__main__":
    import json
    print(json.dumps(rendimiento()))
