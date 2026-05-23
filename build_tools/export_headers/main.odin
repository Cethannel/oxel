package main

import "core:fmt"
import "core:odin/ast"
import "core:odin/parser"
import "core:os"
import "core:path/filepath"
import "core:strings"
main :: proc() {
	input_file_path := os.args[1]

	out_file_path := os.args[2]

	out_file, err := os.open(out_file_path, os.O_WRONLY | os.O_TRUNC)
	if err != nil {
		fmt.panicf("Failed to create output file: %v\n", err)
	}

	pkg, ok := parser.parse_package_from_path(input_file_path)
	assert(ok)

	for name, file in pkg.files {
		decl_loop: for decl in file.decls {
			if !strings.ends_with(decl.pos.file, "block.odin") {
				continue
			}
			if decl.pos.line < 260 {
				continue
			}
			#partial switch n in decl.derived {
			case ^ast.Value_Decl:
				export: bool = false
				maybe_name: Maybe(string) = nil
				for attrib in n.attributes {
					export, maybe_name = get_export_name(attrib)
					if export {
						break
					}
				}
				if !export {
					continue decl_loop
				}
				name := maybe_name.? or_else n.names[0].derived_expr.(^ast.Ident).name
				for value in n.values {
					do_export_value(out_file, value, name)
				}
			case:
			//fmt.printf("Other: %v\n", decl.derived)
			}
		}
	}
}

get_export_name :: proc(attrib: ^ast.Attribute) -> (export: bool = false, name: Maybe(string)) {
	for elem in attrib.elems {
		#partial switch e in elem.derived {
		case ^ast.Ident:
			if e.name == "export" {
				export = true
			}
		case ^ast.Field_Value:
			#partial switch field in e.field.derived_expr {
			case ^ast.Ident:
				if field.name != "link_name" {
					continue
				}
			case:
				continue
			}

			#partial switch value in e.value.derived_expr {
			case ^ast.Basic_Lit:
				name = strings.trim(value.tok.text, "\"")
			case:
				fmt.panicf("Unkown value: %v", e.value.derived_expr)
			}
		}
	}

	return
}

do_export_value :: proc(out_file: os.Handle, expr: ^ast.Expr, name: string) {
	#partial switch e in expr.derived_expr {
	case ^ast.Proc_Lit:
		export_proc_c(out_file, e.type, name)
	case:
		fmt.panicf("Unkown value type: %v\n", e)
	}
}

export_proc_c :: proc(out_file: os.Handle, type: ^ast.Proc_Type, name: string) {
	switch cc in type.calling_convention {
	case string:
		if cc != "\"c\"" {
			fmt.panicf("Unkown calling conv: `%s`\n", cc)
		}
	case ast.Proc_Calling_Convention_Extra:
		fmt.panicf("Unkown calling conv extra: %v\n", cc)
	}

	if type.results != nil {
		if len(type.results.list) != 1 {
			fmt.panicf("Return must be 0 or 1 values")
		}
		export_type_c(out_file, type.results.list[0].type)
	} else {
		os.write_string(out_file, "void ")
	}

	fmt.fprintf(out_file, "%s(", name)

	if type.params != nil {
		for param, i in type.params.list {
			if i > 0 {
				os.write_string(out_file, ", ")
			}
			export_param_c(out_file, param)
		}
	}

	fmt.fprint(out_file, ");\n")
}

export_type_c :: proc(out_file: os.Handle, type: ^ast.Expr) {
	#partial switch t in type.derived_expr {
	case ^ast.Ident:
		file_name := filepath.short_stem(type.pos.file)
		fmt.fprintf(out_file, "moden_%s_%s ", file_name, t.name)
	case ^ast.Pointer_Type:
		os.write_string(out_file, "*")
		export_type_c(out_file, t.elem)
	case:
		fmt.panicf("Unknown type: %v", t)
	}
}

export_param_c :: proc(out_file: os.Handle, param: ^ast.Field) {
	export_type_c(out_file, param.type)
	if len(param.names) > 0 {
		ident := param.names[0].derived_expr.(^ast.Ident)
		name := strings.trim(ident.name, "\"")
		os.write_string(out_file, name)
	}
}
