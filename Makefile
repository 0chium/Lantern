ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0

INSTALL_TARGET_PROCESSES = cameracaptured

TWEAK_NAME = Lantern

Lantern_FILES = Tweak.xm
Lantern_CFLAGS = -fobjc-arc
Lantern_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/makefiles/tweak.mk
