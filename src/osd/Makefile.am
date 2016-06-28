libosd_types_la_SOURCES = \
	osd/PGLog.cc \
	osd/osd_types.cc \
	osd/ECUtil.cc
libosd_types_la_CXXFLAGS = ${AM_CXXFLAGS}
noinst_LTLIBRARIES += libosd_types.la

if ENABLE_SERVER
if WITH_OSD

libosd_a_SOURCES = \
	osd/PG.cc \
	osd/ReplicatedPG.cc \
	osd/ReplicatedBackend.cc \
	osd/ECBackend.cc \
	osd/ECMsgTypes.cc \
	osd/ECTransaction.cc \
	osd/PGBackend.cc \
	osd/HitSet.cc \
	osd/OSD.cc \
	osd/OSDCap.cc \
	osd/Watch.cc \
	osd/ClassHandler.cc \
	osd/OpRequest.cc \
	osd/SnapMapper.cc \
	osd/ScrubStore.cc \
	osd/mClockOpClassAdapter.cc \
        dmclock/src/dmclock_util.cc \
        dmclock/support/src/run_every.cc \
	objclass/class_api.cc

libosd_a_CXXFLAGS = ${AM_CXXFLAGS} -Idmclock/src -Idmclock/support/src
libosd_a_LIBADD =
noinst_LIBRARIES += libosd.a

noinst_HEADERS += \
	osd/ClassHandler.h \
	osd/HitSet.h \
	osd/OSD.h \
	osd/OSDCap.h \
	osd/OSDMap.h \
	osd/ObjectVersioner.h \
	osd/OpRequest.h \
	osd/SnapMapper.h \
	osd/PG.h \
	osd/PGLog.h \
	osd/ReplicatedPG.h \
	osd/PGBackend.h \
	osd/ReplicatedBackend.h \
	osd/TierAgentState.h \
	osd/ECBackend.h \
	osd/ECUtil.h \
	osd/ECMsgTypes.h \
	osd/ECTransaction.h \
	osd/Watch.h \
	osd/ScrubStore.h \
	osd/osd_types.h \
        common/mClockPriorityQueue.h \
	dmclock/src/dmclock_server.h \
	dmclock/src/dmclock_client.h \
	dmclock/src/dmclock_util.h \
	dmclock/support/src/indirect_intrusive_heap.h \
	dmclock/support/src/run_every.h \
	dmclock/support/src/profile.h


endif # WITH_OSD
endif # ENABLE_SERVER
