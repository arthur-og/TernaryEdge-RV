USER_APP_VERSION = 1.0
USER_APP_SITE = $(BR2_EXTERNAL_TERNARYEDGE_RV_PATH)/../user_app
USER_APP_SITE_METHOD = local

USER_APP_DEPENDENCIES = npu-hal

define USER_APP_BUILD_CMDS
    cp $(BR2_EXTERNAL_TERNARYEDGE_RV_PATH)/../npu_hal/npu_hal.h $(@D)/
    cp $(BR2_EXTERNAL_TERNARYEDGE_RV_PATH)/../npu_hal/npu_hal_internal.h $(@D)/
    cp $(BR2_EXTERNAL_TERNARYEDGE_RV_PATH)/../npu_hal/npu_classifier.h $(@D)/
    cp $(BR2_EXTERNAL_TERNARYEDGE_RV_PATH)/../npu_hal/npu_weights.h $(@D)/
    cp $(BR2_EXTERNAL_TERNARYEDGE_RV_PATH)/../include/npu_ioctl.h $(@D)/
    $(TARGET_CC) -Wall -Wextra -O2 -static \
        -I$(@D) \
        -o $(@D)/npu_inference \
        $(@D)/user_app.c \
        -L$(BUILD_DIR)/npu-hal-1.0 -lnpu_hal -lm
endef

define USER_APP_INSTALL_TARGET_CMDS
    $(INSTALL) -D -m 0755 $(@D)/npu_inference $(TARGET_DIR)/usr/bin/npu_inference
endef

$(eval $(generic-package))
