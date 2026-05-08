# Makefile для сборки модуля ядра TOTAL Shield

# Имя модуля
obj-m := total_shield_driver.o

# Путь к исходникам ядра (измените под вашу систему или используйте переменную окружения)
KERNELDIR ?= /lib/modules/$(shell uname -r)/build

# Путь к текущей директории
PWD := $(shell pwd)

all:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) clean

install:
	sudo insmod total_shield_driver.ko

remove:
	sudo rmmod total_shield_driver

info:
	modinfo total_shield_driver.ko

.PHONY: all clean install remove info
