# swift-evolve

This tool randomly permutes Swift source code in ways that should be safe for
resilience. You can then rebuild the dylibs with the modified source, drop them
into an existing binary distribution, and test that nothing breaks.
