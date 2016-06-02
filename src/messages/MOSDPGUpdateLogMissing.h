// -*- mode:C++; tab-width:8; c-basic-offset:2; indent-tabs-mode:t -*-
// vim: ts=8 sw=2 smarttab
/*
 * Ceph - scalable distributed file system
 *
 * Copyright (C) 2004-2006 Sage Weil <sage@newdream.net>
 *
 * This is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License version 2.1, as published by the Free Software
 * Foundation.  See file COPYING.
 *
 */


#ifndef CEPH_MOSDPGUPDATELOGMISSING_H
#define CEPH_MOSDPGUPDATELOGMISSING_H

#include "msg/Message.h"

class MOSDPGUpdateLogMissing : public Message {

  static const int HEAD_VERSION = 2;
  static const int COMPAT_VERSION = 1;


public:
  epoch_t map_epoch;
  spg_t pgid;
  shard_id_t from;
  ceph_tid_t rep_tid;
  list<pg_log_entry_t> entries;
  bool handle_missing; // whether this sent for lost/missing objects,
		       // or just for adding error entries for dup
		       // detection

  epoch_t get_epoch() const { return map_epoch; }
  spg_t get_pgid() const { return pgid; }
  epoch_t get_query_epoch() const { return map_epoch; }
  ceph_tid_t get_tid() const { return rep_tid; }

  MOSDPGUpdateLogMissing() :
    Message(MSG_OSD_PG_UPDATE_LOG_MISSING, HEAD_VERSION, COMPAT_VERSION) { }
  MOSDPGUpdateLogMissing(
    const list<pg_log_entry_t> &entries,
    spg_t pgid,
    shard_id_t from,
    epoch_t epoch,
    bool handle_missing,
    ceph_tid_t rep_tid)
    : Message(MSG_OSD_PG_UPDATE_LOG_MISSING, HEAD_VERSION, COMPAT_VERSION),
      map_epoch(epoch),
      pgid(pgid),
      from(from),
      rep_tid(rep_tid),
      entries(entries),
      handle_missing(handle_missing) {}

private:
  ~MOSDPGUpdateLogMissing() {}

public:
  const char *get_type_name() const { return "PGUpdateLogMissing"; }
  void print(ostream& out) const {
    out << "pg_update_log_missing(" << pgid << " epoch " << map_epoch
	<< " rep_tid " << rep_tid
	<< " entries " << entries << " handle_missing " << handle_missing
	<< ")";
  }

  void encode_payload(uint64_t features) {
    ::encode(map_epoch, payload);
    ::encode(pgid, payload);
    ::encode(from, payload);
    ::encode(rep_tid, payload);
    ::encode(entries, payload);
    ::encode(handle_missing, payload);
  }
  void decode_payload() {
    bufferlist::iterator p = payload.begin();
    ::decode(map_epoch, p);
    ::decode(pgid, p);
    ::decode(from, p);
    ::decode(rep_tid, p);
    ::decode(entries, p);
    if (header.version >= 2) {
      ::decode(handle_missing, p);
    } else {
      handle_missing = true;
    }
  }
};

#endif
