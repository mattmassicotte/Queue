# ``Queue``

<!--@START_MENU_TOKEN@-->Summary<!--@END_MENU_TOKEN@-->

## Overview

This package exposes a single type: ``AsyncQueue``.

Conceptually, ``AsyncQueue`` is very similar to a ``DispatchQueue`` or ``OperationQueue``. However, unlike these an ``AsyncQueue`` can accept async blocks. This exists to more easily enforce ordering across unstructured tasks without requiring explicit dependencies between them.
