# Symbol Versioning

ruby と openssl 編

## とある SL6 の openssl

openssl-devel-1.0.1e-16.el6_5.7.x86_64

```
$ objdump -p /usr/lib64/libcrypto.so

Version definitions:
1 0x01 0x0af47420 libcrypto.so.10
2 0x00 0x0af47420 libcrypto.so.10
3 0x00 0x066a2b21 OPENSSL_1.0.1
4 0x00 0x02b21533 OPENSSL_1.0.1_EC
```

OPENSSL_1.0.1_EC なる symbol version が含まれている

## とある EC2

openssl-devel-1.0.1e-4.58.amzn1.x86_64

```
$ objdump -p /usr/lib64/libcrypto.so

Version definitions:
1 0x01 0x0af47420 libcrypto.so.10
2 0x00 0x0af47420 libcrypto.so.10
3 0x00 0x066a2b21 OPENSSL_1.0.1
```

## SL6 でビルドした ruby の openssl.so

```
$ objdump -p /usr/local/rbenv/versions/1.9.3-p545/lib/ruby/1.9.1/x86_64-linux/openssl.so

Version References:
  required from libc.so.6:
    0x09691a75 0x00 06 GLIBC_2.2.5
  required from libpthread.so.0:
    0x09691a75 0x00 05 GLIBC_2.2.5
  required from libssl.so.10:
    0x0a779bd0 0x00 03 libssl.so.10
  required from libcrypto.so.10:
    0x02b21533 0x00 04 OPENSSL_1.0.1_EC
    0x0af47420 0x00 02 libcrypto.so.10
```

libcrypto.so.10 から ***OPENSSL_1.0.1_EC*** を要求されている

```
$ objdump -T /usr/local/rbenv/versions/1.9.3-p545/lib/ruby/1.9.1/x86_64-linux/openssl.so | grep OPENSSL

0000000000000000      DF *UND*  0000000000000000  libcrypto.so.10 OPENSSL_add_all_algorithms_noconf
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC ECPKParameters_print
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_GROUP_clear_free
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_KEY_get0_group
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_POINT_make_affine
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_GROUP_set_seed
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_GROUP_get_order
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_GROUP_new
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_GFp_mont_method
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_POINT_set_to_infinity
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_GROUP_dup
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_GROUP_get0_generator
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_GROUP_get_curve_name
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_GROUP_get_cofactor
0000000000000000      DF *UND*  0000000000000000  libcrypto.so.10 OPENSSL_cleanse
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_GROUP_set_point_conversion_form
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_POINT_bn2point
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_POINT_new
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_POINT_clear_free
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_KEY_check_key
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_KEY_print
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC ECDH_compute_key
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_GROUP_set_generator
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_KEY_generate_key
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_POINT_dup
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_GROUP_new_by_curve_name
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_get_builtin_curves
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_KEY_set_public_key
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_GROUP_set_asn1_flag
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_POINT_point2bn
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_POINT_is_at_infinity
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_GROUP_get_point_conversion_form
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC ECDSA_size
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_KEY_get0_private_key
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC ECDSA_verify
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_POINT_cmp
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_POINT_invert
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC ECDSA_sign
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_GROUP_new_curve_GFp
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_GROUP_get_degree
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_KEY_set_asn1_flag
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_GROUP_get_seed_len
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_GROUP_get0_seed
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_POINT_is_on_curve
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_KEY_set_conv_form
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_KEY_set_private_key
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_KEY_free
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_KEY_dup
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_GFp_simple_method
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_KEY_set_group
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_KEY_new_by_curve_name
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_GROUP_cmp
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_KEY_get0_public_key
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_KEY_new
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_GROUP_get_asn1_flag
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_GFp_nist_method
```

```
$ objdump -T /usr/lib64/libssl.so | grep EC
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_KEY_get0_group
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_POINT_point2oct
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_POINT_copy
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_GROUP_get_curve_name
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_POINT_new
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC ECDH_compute_key
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_KEY_generate_key
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_GROUP_new_by_curve_name
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_KEY_set_public_key
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_KEY_get0_private_key
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC ECDSA_verify
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC ECDSA_sign
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_POINT_oct2point
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_GROUP_get_degree
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_GROUP_free
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_KEY_set_private_key
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_KEY_free
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_KEY_dup
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_METHOD_get_field_type
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_KEY_set_group
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_KEY_get0_public_key
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_POINT_free
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_KEY_new
0000000000000000      DF *UND*  0000000000000000  OPENSSL_1.0.1_EC EC_KEY_up_ref
0000000000000000 g    DO *ABS*  0000000000000000  OPENSSL_1.0.1_EC OPENSSL_1.0.1_EC

## EC2

libssl.so に OPENSSL_1.0.1_EC のシンボルが無い

```
$ objdump -T /usr/lib64/libssl.so | grep EC
```

```n
$ objdump -T /usr/local/rbenv/versions/1.9.3-p484/lib/ruby/1.9.1/x86_64-linux/openssl.so | grep OPENSSL
0000000000000000      DF *UND*  0000000000000000              OPENSSL_add_all_algorithms_noconf
0000000000000000      DF *UND*  0000000000000000              OPENSSL_cleanse
```

OPENSSL_1.0.1_EC は必要ない

```
$ objdump -p /usr/local/rbenv/versions/1.9.3-p484/lib/ruby/1.9.1/x86_64-linux/openssl.so

Version References:
  required from libc.so.6:
    0x09691a75 0x00 03 GLIBC_2.2.5
  required from libpthread.so.0:
    0x09691a75 0x00 02 GLIBC_2.2.5
```