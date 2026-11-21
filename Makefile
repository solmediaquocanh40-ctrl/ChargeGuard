export TARGET := iphone:clang:latest:14.0
export ARCHS := arm64 arm64e

include $(THEOS)/makefiles/common.mk

SUBPROJECTS = tweak prefs daemon app

include $(THEOS_MAKE_PATH)/aggregate.mk
