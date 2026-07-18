NPU_HAL_VERSION = 1.0
NPU_HAL_SITE = $(BR2_EXTERNAL_TERNARYEDGE_RV_PATH)/../npu_hal
NPU_HAL_SITE_METHOD = local

define NPU_HAL_BUILD_CMDS
    $(MAKE) -C $(@D) CC=$(TARGET_CC) AR=$(TARGET_AR)
endef

define NPU_HAL_INSTALL_STAGING_CMDS
    $(INSTALL) -D -m 0644 $(@D)/libnpu_hal.a $(STAGING_DIR)/usr/lib/libnpu_hal.a
    $(INSTALL) -D -m 0644 $(@D)/npu_hal.h $(STAGING_DIR)/usr/include/npu_hal.h
    $(INSTALL) -D -m 0644 $(@D)/npu_hal_internal.h $(STAGING_DIR)/usr/include/npu_hal_internal.h
    $(INSTALL) -D -m 0644 $(@D)/npu_classifier.h $(STAGING_DIR)/usr/include/npu_classifier.h
    $(INSTALL) -D -m 0644 $(@D)/npu_weights.h $(STAGING_DIR)/usr/include/npu_weights.h
endef

define NPU_HAL_INSTALL_TARGET_CMDS
    $(INSTALL) -D -m 0644 $(@D)/libnpu_hal.a $(TARGET_DIR)/usr/lib/libnpu_hal.a
endef

$(eval $(generic-package))
