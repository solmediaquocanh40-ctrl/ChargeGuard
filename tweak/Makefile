TARGET := iphone:clang:latest:14.0
ARCHS := arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ChargeGuard

ChargeGuard_FILES = Tweak.x
ChargeGuard_FRAMEWORKS = UIKit CoreLocation EventKit AudioToolbox
ChargeGuard_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-error

include $(THEOS_MAKE_PATH)/tweak.mk
