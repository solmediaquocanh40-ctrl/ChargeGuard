TARGET := iphone:clang:latest:14.0
ARCHS := arm64 arm64e

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = ChargeGuard

ChargeGuard_FILES = main.m CGAppDelegate.m CGTheme.m CGHomeViewController.m CGChartViewController.m CGMoreViewController.m
ChargeGuard_FRAMEWORKS = UIKit Foundation PhotosUI UniformTypeIdentifiers
ChargeGuard_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-error
ChargeGuard_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk
