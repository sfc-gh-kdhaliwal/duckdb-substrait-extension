//===----------------------------------------------------------------------===//
//                         DuckDB
//
// from_substrait_ast.hpp
//
// AST-based Substrait to DuckDB transformer (no Relation binding)
//
//===----------------------------------------------------------------------===//

#pragma once

#include <string>
#include <unordered_map>
#include "substrait/plan.pb.h"
#include "duckdb/main/client_context.hpp"
#include "duckdb/parser/query_node.hpp"
#include "duckdb/parser/tableref.hpp"
#include "duckdb/parser/parsed_expression.hpp"

namespace duckdb {

//! SubstraitToAST transforms Substrait plans directly to DuckDB AST nodes
//! without creating Relations. This avoids lock re-entrancy issues when
//! called during bind operations.
class SubstraitToAST {
public:
	SubstraitToAST(ClientContext &context, const string &serialized, bool json = false);

	//! Transforms Substrait Plan to DuckDB TableRef (pure AST, no binding)
	unique_ptr<TableRef> TransformPlanToTableRef();

private:
	//! Transforms Substrait Plan Root to a TableRef
	unique_ptr<TableRef> TransformRootOp(const substrait::RelRoot &sop);

	//! Transform Substrait Read operation to TableRef
	unique_ptr<TableRef> TransformReadOp(const substrait::Rel &sop);

	//! Transform Substrait Expressions to DuckDB ParsedExpressions
	unique_ptr<ParsedExpression> TransformExpr(const substrait::Expression &sexpr);
	static unique_ptr<ParsedExpression> TransformLiteralExpr(const substrait::Expression &sexpr);

	//! Transform literal value
	static Value TransformLiteralToValue(const substrait::Expression_Literal &literal);

	//! Client Context (not used for binding, just for configuration)
	ClientContext &context;

	//! Substrait Plan
	substrait::Plan plan;

	//! Function registry
	unordered_map<uint64_t, string> functions_map;
};

} // namespace duckdb
