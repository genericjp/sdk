// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
// VMOptions=--optimization_counter_threshold=10 --no-background_compilation

import 'dart:typed_data';
import 'package:expect/expect.dart';

unalignedFloat32() {
  var bytes = new ByteData(64);
  bytes.setFloat32(0, 16.25, Endianness.HOST_ENDIAN);
  Expect.equals(16.25, bytes.getFloat32(0, Endianness.HOST_ENDIAN));
  bytes.setFloat32(1, 32.125, Endianness.HOST_ENDIAN);
  Expect.equals(32.125, bytes.getFloat32(1, Endianness.HOST_ENDIAN));
  bytes.setFloat32(2, 16.25, Endianness.HOST_ENDIAN);
  Expect.equals(16.25, bytes.getFloat32(2, Endianness.HOST_ENDIAN));
  bytes.setFloat32(3, 32.125, Endianness.HOST_ENDIAN);
  Expect.equals(32.125, bytes.getFloat32(3, Endianness.HOST_ENDIAN));
}

unalignedFloat64() {
  var bytes = new ByteData(64);
  bytes.setFloat64(0, 16.25, Endianness.HOST_ENDIAN);
  Expect.equals(16.25, bytes.getFloat64(0, Endianness.HOST_ENDIAN));
  bytes.setFloat64(1, 32.125, Endianness.HOST_ENDIAN);
  Expect.equals(32.125, bytes.getFloat64(1, Endianness.HOST_ENDIAN));
  bytes.setFloat64(2, 16.25, Endianness.HOST_ENDIAN);
  Expect.equals(16.25, bytes.getFloat64(2, Endianness.HOST_ENDIAN));
  bytes.setFloat64(3, 32.125, Endianness.HOST_ENDIAN);
  Expect.equals(32.125, bytes.getFloat64(3, Endianness.HOST_ENDIAN));
  bytes.setFloat64(4, 16.25, Endianness.HOST_ENDIAN);
  Expect.equals(16.25, bytes.getFloat64(4, Endianness.HOST_ENDIAN));
  bytes.setFloat64(5, 32.125, Endianness.HOST_ENDIAN);
  Expect.equals(32.125, bytes.getFloat64(5, Endianness.HOST_ENDIAN));
  bytes.setFloat64(6, 16.25, Endianness.HOST_ENDIAN);
  Expect.equals(16.25, bytes.getFloat64(6, Endianness.HOST_ENDIAN));
  bytes.setFloat64(7, 32.125, Endianness.HOST_ENDIAN);
  Expect.equals(32.125, bytes.getFloat64(7, Endianness.HOST_ENDIAN));
}

main() {
  for (var i = 0; i < 20; i++) {
    unalignedFloat32();
    unalignedFloat64();
  }
}
