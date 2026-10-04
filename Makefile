THEOS ?= $(HOME)/theos

ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME = rootless

INSTALL_TARGET_PROCESSES = cameracaptured

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Lantern

Lantern_FILES = Tweak.xm
Lantern_CFLAGS = -fobjc-arc
Lantern_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
