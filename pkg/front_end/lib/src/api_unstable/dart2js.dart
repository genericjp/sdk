// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async' show Future;

import 'package:kernel/kernel.dart' show Component;

import 'package:kernel/target/targets.dart' show Target;

import '../api_prototype/compiler_options.dart' show CompilerOptions;

import '../api_prototype/diagnostic_message.dart' show DiagnosticMessageHandler;

import '../api_prototype/file_system.dart' show FileSystem;

import '../base/processed_options.dart' show ProcessedOptions;

import '../fasta/compiler_context.dart' show CompilerContext;

import '../fasta/fasta_codes.dart' show messageMissingMain;

import '../fasta/severity.dart' show Severity;

import '../kernel_generator_impl.dart' show generateKernelInternal;

import '../fasta/scanner.dart' show ErrorToken, StringToken, Token;

import 'compiler_state.dart' show InitializedCompilerState;

export '../api_prototype/compiler_options.dart' show CompilerOptions;

export '../api_prototype/diagnostic_message.dart' show DiagnosticMessage;

export '../api_prototype/file_system.dart'
    show FileSystem, FileSystemEntity, FileSystemException;

export '../api_prototype/kernel_generator.dart' show kernelForProgram;

export '../api_prototype/standard_file_system.dart' show DataFileSystemEntity;

export '../compute_platform_binaries_location.dart'
    show computePlatformBinariesLocation;

export '../fasta/fasta_codes.dart' show FormattedMessage;

export '../fasta/kernel/redirecting_factory_body.dart'
    show RedirectingFactoryBody;

export '../fasta/operator.dart' show operatorFromString;

export '../fasta/parser/async_modifier.dart' show AsyncModifier;

export '../fasta/scanner.dart' show isUserDefinableOperator, isMinusOperator;

export '../fasta/scanner/characters.dart'
    show
        $$,
        $0,
        $9,
        $A,
        $BACKSLASH,
        $CR,
        $DEL,
        $DQ,
        $HASH,
        $LF,
        $LS,
        $PS,
        $TAB,
        $Z,
        $_,
        $a,
        $g,
        $s,
        $z;

export '../fasta/severity.dart' show Severity;

export '../fasta/util/link.dart' show Link, LinkBuilder;

export '../fasta/util/link_implementation.dart' show LinkEntry;

export '../fasta/util/relativize.dart' show relativizeUri;

export 'compiler_state.dart' show InitializedCompilerState;

void clearStringTokenCanonicalizer() {
  // TODO(ahe): We should be able to remove this. Fasta should take care of
  // clearing the cache when.
  StringToken.canonicalizer.clear();
}

InitializedCompilerState initializeCompiler(
    InitializedCompilerState oldState,
    Target target,
    Uri librariesSpecificationUri,
    Uri sdkPlatformUri,
    Uri packagesFileUri) {
  if (oldState != null &&
      oldState.options.packagesFileUri == packagesFileUri &&
      oldState.options.librariesSpecificationUri == librariesSpecificationUri &&
      oldState.options.linkedDependencies[0] == sdkPlatformUri) {
    return oldState;
  }

  CompilerOptions options = new CompilerOptions()
    ..target = target
    ..strongMode = target.strongMode
    ..linkedDependencies = [sdkPlatformUri]
    ..librariesSpecificationUri = librariesSpecificationUri
    ..packagesFileUri = packagesFileUri;

  ProcessedOptions processedOpts = new ProcessedOptions(options: options);

  return new InitializedCompilerState(options, processedOpts);
}

Future<Component> compile(
    InitializedCompilerState state,
    bool verbose,
    FileSystem fileSystem,
    DiagnosticMessageHandler onDiagnostic,
    Uri input) async {
  CompilerOptions options = state.options;
  options
    ..onDiagnostic = onDiagnostic
    ..verbose = verbose
    ..fileSystem = fileSystem;

  ProcessedOptions processedOpts = state.processedOpts;
  processedOpts.inputs.clear();
  processedOpts.inputs.add(input);
  processedOpts.clearFileSystemCache();

  var compilerResult = await CompilerContext.runWithOptions(processedOpts,
      (CompilerContext context) async {
    var compilerResult = await generateKernelInternal();
    Component component = compilerResult?.component;
    if (component == null) return null;
    if (component.mainMethod == null) {
      context.options.report(
          messageMissingMain.withLocation(input, -1, 0), Severity.error);
      return null;
    }
    return compilerResult;
  });

  // Remove these parameters from [options] - they are no longer needed and
  // retain state from the previous compile. (http://dartbug.com/33708)
  options.onDiagnostic = null;
  options.fileSystem = null;
  return compilerResult?.component;
}

Object tokenToString(Object value) {
  // TODO(ahe): This method is most likely unnecessary. Dart2js doesn't see
  // tokens anymore.
  if (value is ErrorToken) {
    // Shouldn't happen.
    return value.assertionMessage.message;
  } else if (value is Token) {
    return value.lexeme;
  } else {
    return value;
  }
}
