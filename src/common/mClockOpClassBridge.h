// -*- mode:C++; tab-width:8; c-basic-offset:2; indent-tabs-mode:t -*-
// vim: ts=8 sw=2 smarttab
/*
 * Ceph - scalable distributed file system
 *
 * Copyright (C) 2016 Red Hat Inc.
 *
 * This is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License version 2.1, as published by the Free Software
 * Foundation.  See file COPYING.
 *
 */


#pragma once


#include "mClockPriorityQueue.h"


namespace ceph {

  namespace dmc = crimson::dmclock;

  enum class osd_op_type_t {
    client, osd_subop, bg_snaptrim, bg_recovery, bg_scrub };

  struct mclock_op_tags_t {
    const double client_op_res;
    const double client_op_wgt;
    const double client_op_lim;

    const double osd_subop_res;
    const double osd_subop_wgt;
    const double osd_subop_lim;

    const double snap_res;
    const double snap_wgt;
    const double snap_lim;

    const double recov_res;
    const double recov_wgt;
    const double recov_lim;

    const double scrub_res;
    const double scrub_wgt;
    const double scrub_lim;

    mclock_op_tags_t(CephContext *cct) :
      client_op_res(cct->_conf->osd_op_queue_mclock_client_op_res),
      client_op_wgt(cct->_conf->osd_op_queue_mclock_client_op_wgt),
      client_op_lim(cct->_conf->osd_op_queue_mclock_client_op_lim),

      osd_subop_res(cct->_conf->osd_op_queue_mclock_osd_subop_res),
      osd_subop_wgt(cct->_conf->osd_op_queue_mclock_osd_subop_wgt),
      osd_subop_lim(cct->_conf->osd_op_queue_mclock_osd_subop_lim),

      snap_res(cct->_conf->osd_op_queue_mclock_snap_res),
      snap_wgt(cct->_conf->osd_op_queue_mclock_snap_wgt),
      snap_lim(cct->_conf->osd_op_queue_mclock_snap_lim),

      recov_res(cct->_conf->osd_op_queue_mclock_recov_res),
      recov_wgt(cct->_conf->osd_op_queue_mclock_recov_wgt),
      recov_lim(cct->_conf->osd_op_queue_mclock_recov_lim),

      scrub_res(cct->_conf->osd_op_queue_mclock_scrub_res),
      scrub_wgt(cct->_conf->osd_op_queue_mclock_scrub_wgt),
      scrub_lim(cct->_conf->osd_op_queue_mclock_scrub_lim)
    {
      // empty
    }
  };

  std::unique_ptr<mclock_op_tags_t> mclock_op_tags;


  dmc::ClientInfo op_class_client_info_f(const osd_op_type_t& op_type) {
    static dmc::ClientInfo _default(1.0, 1.0, 1.0);
    return _default;
  }


#if 0
  // turn cost, which can range from 1000 to 50 * 2^20
  double cost_to_tag(unsigned cost) {
    static const double log_of_2 = std::log(2.0);
    return cost_factor * std::log(cost) / log_of_2;
  }
#endif


  template<typename T, typename K>
  class mClockOpClassQueue : public mClockQueue<T, osd_op_type_t> {

    using super = mClockQueue<T, osd_op_type_t>;

    double cost_factor;

    public:
    
    mClockOpClassQueue(CephContext *cct) :
      super(&op_class_client_info_f),
      cost_factor(cct->_conf->osd_op_queue_mclock_cost_factor)
    {
      // 
    }

#if 0
    void enqueue_strict(K cl, unsigned priority, T item) override final {
      high_queue[priority].enqueue(cl, 0, item);
    }

    
    void enqueue_strict_front(K cl, unsigned priority, T item) override final {
      high_queue[priority].enqueue_front(cl, 0, item);
    }

    
    void enqueue(K cl, unsigned priority, unsigned cost, T item) override final {
      double tag_cost = cost_to_tag(cost);
      osd_op_type_t op_type = osd_op_type_t::client;
      queue.add_request(item, op_type, tag_cost);
    }

    
    void enqueue_front(K cl, unsigned priority, unsigned cost, T item) override final {
      queue_front.emplace_front(std::pair<K,T>(cl, item));
    }
#endif
  }; // class mClockOpClassQueue
  
} // namespace ceph
