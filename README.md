# FFXIV Classic Zipatch Extractor/Viewer

A tool for extracting and viewing zipatch files from Final Fantasy XIV Classic (1.0). This project allows you to analyze and extract data from FFXIV's patch format.

## Features

- Extract and view contents of FFXIV Classic zipatch files
- Support for various zipatch component types (ADIR, APLY, DELD, ETRY, FHDR)
- Command-line interface for easy integration into workflows

## Installation

1. Make sure you have Zig installed (this project uses Zig as its programming language)
2. Clone this repository:
```
git clone [your-repository-url]
cd zipath
```
3. Build the project:
```
zig build
```

## Usage

Run the extractor on a zipatch file:

```
zig-out/bin/zipatch_reader [options] [path-to-zipatch-file]
```

The extracted files will be placed in the `output/` directory.

## File Format Support

This tool supports the FFXIV Classic zipatch format, including:
- ADIR (Directory information)
- APLY (Apply data)
- DELD (Delete operations)
- ETRY (Entry data)
- FHDR (File headers)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Feel free to submit pull requests or open issues for bugs and feature requests.

## Acknowledgements

- Square Enix for creating Final Fantasy XIV
- The FFXIV archiving community for documenting the zipatch format
