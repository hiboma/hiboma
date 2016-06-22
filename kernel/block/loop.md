
```
struct gendisk
 - kmalloc_node
 - minor 番号
 - disk_name    ... "loop%d"
 - queue        ... struct request_queue_t
 - private_data ... struct loop_device
     - lo_queue ... struct request_queue_t
     - major 番号 = 7
```

 * struc gendisk は add_disk ( blk_register_region, register_disk, blk_register_queue ) で追加

# BIO のハンドリング

## request を消費する側

loop_thread が待機している

 * loop_handle_bio 
   * WRITE lo_send
     * do_lo_send_write
        * .transfer = { transfer_none, transfer_xor }
        * __do_lo_send_write
          * (struct file *)lo_backing_file->f_op_->write を呼び出す
     * do_lo_send_aops
       * lo_backing_file->file->f_mapping の address_space_operations -> prepare_write
       * lo_do_transfer
         * .transfer = { transfer_none, transfer_xor } /* 暗号化の有無 */
           * memcpy で page 間でデータをコピーする
           * page のデータをデバイスに転送するのは誰の役目? -> lo_backing_file
       * lo_backing_file->file->f_mapping の address_space_operations -> commit_write
   * READ  lo_receive
     * do_lo_receive
       * lo_backing_file->file->f_op->sendfile
          * lo_read_actor -> .transfer = { transfer_none, transfer_xor }
          * .transfer はページ間のコピー実装か?

## loop_make_request

 * blk_queue_make_request(lo->lo_queue, loop_make_request);