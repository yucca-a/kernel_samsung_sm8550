obj-y := rekernel.o
rekernel-y := rekernel_main.o rekernel_netlink.o rekernel_binder.o rekernel_signal.o rekernel_netfilter.o
ifdef REKERNEL_VERSION
ccflags-y += -DREKERNEL_VERSION=\"$(REKERNEL_VERSION)\"
endif

ccflags-$(CONFIG_REKERNEL_NETWORK) += -DNETWORK_FILTER
ccflags-$(CONFIG_REKERNEL_LEGACY_NETLINK) += -DLEGACY_NETLINK
