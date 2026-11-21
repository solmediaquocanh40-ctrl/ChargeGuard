TARGET := iphone:clang:latest:14.0
ARCHS := arm64 arm64e

include $(THEOS)/makefiles/common.mk

TOOL_NAME = chargeguardd

chargeguardd_FILES = main.m
chargeguardd_FRAMEWORKS = IOKit Foundation
chargeguardd_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-error
chargeguardd_CODESIGN_FLAGS = -Sentitlements.plist
chargeguardd_INSTALL_PATH = /usr/libexec

include $(THEOS_MAKE_PATH)/tool.mk
