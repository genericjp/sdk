// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/analysis/declared_variables.dart';
import 'package:analyzer/dart/ast/ast.dart' show CompilationUnit;
import 'package:analyzer/dart/element/element.dart'
    show CompilationUnitElement, LibraryElement;
import 'package:analyzer/src/context/context.dart';
import 'package:analyzer/src/dart/analysis/driver.dart';
import 'package:analyzer/src/dart/analysis/file_state.dart';
import 'package:analyzer/src/dart/analysis/one_phase_summaries_selector.dart';
import 'package:analyzer/src/dart/element/element.dart';
import 'package:analyzer/src/dart/element/handle.dart';
import 'package:analyzer/src/generated/engine.dart'
    show AnalysisContext, AnalysisEngine, AnalysisOptions;
import 'package:analyzer/src/generated/source.dart';
import 'package:analyzer/src/summary/format.dart';
import 'package:analyzer/src/summary/idl.dart';
import 'package:analyzer/src/summary/link.dart';
import 'package:analyzer/src/summary/one_phase.dart';
import 'package:analyzer/src/summary/package_bundle_reader.dart';
import 'package:analyzer/src/summary/summarize_elements.dart';
import 'package:analyzer/src/dart/analysis/byte_store.dart';
import 'package:analyzer/src/dart/analysis/performance_logger.dart';

/**
 * Context information necessary to analyze one or more libraries within an
 * [AnalysisDriver].
 *
 * Currently this is implemented as a wrapper around [AnalysisContext].
 * TODO(paulberry): make a front end API that this can make use of instead.
 */
class LibraryContext {
  final SummaryDataStore store;

  /**
   * The [AnalysisContext] which is used to do the analysis.
   */
  final AnalysisContext analysisContext;

  /**
   * The resynthesizer that resynthesizes elements in [analysisContext].
   */
  final ElementResynthesizer resynthesizer;

  /**
   * Create a [LibraryContext] which is prepared to analyze [targetLibrary].
   */
  factory LibraryContext.forSingleLibrary(
      FileState targetLibrary,
      PerformanceLog logger,
      PackageBundle sdkBundle,
      ByteStore byteStore,
      AnalysisOptions options,
      DeclaredVariables declaredVariables,
      SourceFactory sourceFactory,
      SummaryDataStore externalSummaries,
      FileSystemState fsState) {
    return logger.run('Create library context', () {
      Map<String, FileState> libraries = <String, FileState>{};
      SummaryDataStore store = new SummaryDataStore(const <String>[]);

      if (externalSummaries != null) {
        store.addStore(externalSummaries);
      }

      if (sdkBundle != null) {
        store.addBundle(null, sdkBundle);
      }

      void appendLibraryFiles(FileState library) {
        if (!libraries.containsKey(library.uriStr)) {
          // Serve 'dart:' URIs from the SDK bundle.
          if (sdkBundle != null && library.uri.scheme == 'dart') {
            return;
          }

          if (library.isInExternalSummaries) {
            return;
          }

          libraries[library.uriStr] = library;

          // Append library units.
          for (FileState part in library.libraryFiles) {
            store.addUnlinkedUnit(part.uriStr, part.unlinked);
          }

          // Append referenced libraries.
          library.importedFiles.forEach(appendLibraryFiles);
          library.exportedFiles.forEach(appendLibraryFiles);
        }
      }

      logger.run('Append library files', () {
        appendLibraryFiles(targetLibrary);
      });

      var libraryUrisToLink = new Set<String>();
      var libraryFilesToLink = new Set<FileState>();
      logger.run('Load linked bundles', () {
        for (FileState library in libraries.values) {
          if (library.exists || library == targetLibrary) {
            String key = '${library.transitiveSignature}.linked';
            List<int> bytes = byteStore.get(key);
            if (bytes != null) {
              LinkedLibrary linked = new LinkedLibrary.fromBuffer(bytes);
              store.addLinkedLibrary(library.uriStr, linked);
            } else {
              libraryUrisToLink.add(library.uriStr);
              libraryFilesToLink.add(library);
            }
          }
        }
        int numOfLoaded = libraries.length - libraryUrisToLink.length;
        logger.writeln('Loaded $numOfLoaded linked bundles.');
      });

      Map<String, LinkedLibraryBuilder> linkedLibraries = {};
      if (enableOnePhaseSummaries) {
        var uriToUnit = <String, CompilationUnit>{};
        logger.run('Parse files', () {
          for (var library in libraryFilesToLink) {
            for (var file in library.libraryFiles) {
              uriToUnit[file.uriStr] = file.parse();
            }
          }
          logger.writeln('Parsed ${uriToUnit.length} files.');
        });

        logger.run('Link libraries', () {
          var assembler = new PackageBundleAssembler();
          summarize(uriToUnit, store, assembler, (_) => null, true);

          var bundle = assembler.assemble();
          for (int i = 0; i < bundle.linkedLibraryUris.length; i++) {
            var uri = bundle.linkedLibraryUris[i];

            // TODO(scheglov) At the moment we might get parts here.
            if (!libraries.containsKey(uri)) {
              continue;
            }

            linkedLibraries[uri] = bundle.linkedLibraries[i];
          }

          logger.writeln('Linked ${linkedLibraries.length} libraries.');
        });
      } else {
        logger.run('Link libraries', () {
          linkedLibraries = link(libraryUrisToLink, (String uri) {
            LinkedLibrary linkedLibrary = store.linkedMap[uri];
            return linkedLibrary;
          }, (String uri) {
            UnlinkedUnit unlinkedUnit = store.unlinkedMap[uri];
            return unlinkedUnit;
          }, (_) => null);
          logger.writeln('Linked ${linkedLibraries.length} libraries.');
        });
      }

      for (String uri in linkedLibraries.keys) {
        LinkedLibraryBuilder linkedBuilder = linkedLibraries[uri];
        FileState library = libraries[uri];
        String key = '${library.transitiveSignature}.linked';
        List<int> bytes = linkedBuilder.toBuffer();
        LinkedLibrary linked = new LinkedLibrary.fromBuffer(bytes);
        store.addLinkedLibrary(uri, linked);
        byteStore.put(key, bytes);
      }

      var resynthesizingContext = _createResynthesizingContext(
          options, declaredVariables, sourceFactory, store);
      resynthesizingContext.context.contentCache =
          new _ContentCacheWrapper(fsState);

      return new LibraryContext._(store, resynthesizingContext.context,
          resynthesizingContext.resynthesizer);
    });
  }

  LibraryContext._(this.store, this.analysisContext, this.resynthesizer);

  /**
   * Computes a [CompilationUnitElement] for the given library/unit pair.
   */
  CompilationUnitElement computeUnitElement(
      Source librarySource, Source unitSource) {
    String libraryUri = librarySource.uri.toString();
    String unitUri = unitSource.uri.toString();
    return resynthesizer.getElement(
        new ElementLocationImpl.con3(<String>[libraryUri, unitUri]));
  }

  /**
   * Cleans up any persistent resources used by this [LibraryContext].
   *
   * Should be called once the [LibraryContext] is no longer needed.
   */
  void dispose() {
    analysisContext.dispose();
  }

  /**
   * Return `true` if the given [uri] is known to be a library.
   */
  bool isLibraryUri(Uri uri) {
    String uriStr = uri.toString();
    return store.unlinkedMap[uriStr]?.isPartOf == false;
  }

  /**
   * Resynthesize the [LibraryElement] from the given [store].
   */
  static LibraryElement resynthesizeLibraryElement(
      AnalysisOptions analysisOptions,
      DeclaredVariables declaredVariables,
      SourceFactory sourceFactory,
      SummaryDataStore store,
      String uri) {
    var resynthesizingContext = _createResynthesizingContext(
        analysisOptions, declaredVariables, sourceFactory, store);
    try {
      return resynthesizingContext.resynthesizer
          .getElement(new ElementLocationImpl.con3([uri]));
    } finally {
      resynthesizingContext.context.dispose();
    }
  }

  static _ResynthesizingAnalysisContext _createResynthesizingContext(
      AnalysisOptions analysisOptions,
      DeclaredVariables declaredVariables,
      SourceFactory sourceFactory,
      SummaryDataStore store) {
    AnalysisContextImpl analysisContext =
        AnalysisEngine.instance.createAnalysisContext();
    analysisContext.useSdkCachePartition = false;
    analysisContext.analysisOptions = analysisOptions;
    analysisContext.declaredVariables = declaredVariables;
    analysisContext.sourceFactory = sourceFactory.clone();
    var provider = new InputPackagesResultProvider(analysisContext, store);
    analysisContext.resultProvider = provider;
    return new _ResynthesizingAnalysisContext(
        analysisContext, provider.resynthesizer);
  }
}

/**
 * [ContentCache] wrapper around [FileContentOverlay].
 */
class _ContentCacheWrapper implements ContentCache {
  final FileSystemState fsState;

  _ContentCacheWrapper(this.fsState);

  @override
  void accept(ContentCacheVisitor visitor) {
    throw new UnimplementedError();
  }

  @override
  String getContents(Source source) {
    return _getFileForSource(source).content;
  }

  @override
  bool getExists(Source source) {
    if (source.isInSystemLibrary) {
      return true;
    }
    String uriStr = source.uri.toString();
    if (fsState.externalSummaries != null &&
        fsState.externalSummaries.hasUnlinkedUnit(uriStr)) {
      return true;
    }
    return _getFileForSource(source).exists;
  }

  @override
  int getModificationStamp(Source source) {
    if (source.isInSystemLibrary) {
      return 0;
    }
    return _getFileForSource(source).exists ? 0 : -1;
  }

  @override
  String setContents(Source source, String contents) {
    throw new UnimplementedError();
  }

  FileState _getFileForSource(Source source) {
    String path = source.fullName;
    return fsState.getFileForPath(path);
  }
}

/**
 * Container with analysis context and the corresponding resynthesizer.
 */
class _ResynthesizingAnalysisContext {
  final AnalysisContextImpl context;
  final ElementResynthesizer resynthesizer;

  _ResynthesizingAnalysisContext(this.context, this.resynthesizer);
}
