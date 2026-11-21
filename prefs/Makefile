TARGET := iphone:clang:latest:14.0
ARCHS := arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = ChargeGuardPrefs

ChargeGuardPrefs_FILES = CGRootListController.m CGSliderCell.m
ChargeGuardPrefs_FRAMEWORKS = UIKit UniformTypeIdentifiers
ChargeGuardPrefs_INSTALL_PATH = /Library/PreferenceBundles
ChargeGuardPrefs_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-error
ChargeGuardPrefs_LDFLAGS = -undefined dynamic_lookup

include $(THEOS_MAKE_PATH)/bundle.mk
