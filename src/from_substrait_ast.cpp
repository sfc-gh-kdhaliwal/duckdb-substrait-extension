#include "from_substrait_ast.hpp"

#include "duckdb/parser/query_node/select_node.hpp"
#include "duckdb/parser/tableref/expressionlistref.hpp"
#include "duckdb/parser/tableref/subqueryref.hpp"
#include "duckdb/parser/tableref/basetableref.hpp"
#include "duckdb/parser/expression/constant_expression.hpp"
#include "duckdb/parser/expression/star_expression.hpp"
#include "duckdb/parser/statement/select_statement.hpp"
#include "duckdb/common/exception.hpp"

#include "google/protobuf/util/json_util.h"

namespace duckdb {

SubstraitToAST::SubstraitToAST(ClientContext &context_p, const string &serialized, bool json)
    : context(context_p) {
	if (!json) {
		if (!plan.ParseFromString(serialized)) {
			throw std::runtime_error("Could not parse binary Substrait plan");
		}
	} else {
		google::protobuf::util::Status status = google::protobuf::util::JsonStringToMessage(serialized, &plan);
		if (!status.ok()) {
			throw std::runtime_error("Could not parse JSON Substrait plan: " + status.ToString());
		}
	}

	// Register function extensions
	for (auto &sext : plan.extensions()) {
		if (!sext.has_extension_function()) {
			continue;
		}
		functions_map[sext.extension_function().function_anchor()] = sext.extension_function().name();
	}
}

Value SubstraitToAST::TransformLiteralToValue(const substrait::Expression_Literal &literal) {
	if (literal.has_null()) {
		return Value(LogicalType::SQLNULL);
	}
	switch (literal.literal_type_case()) {
	case substrait::Expression_Literal::LiteralTypeCase::kI8:
		return Value::TINYINT(static_cast<int8_t>(literal.i8()));
	case substrait::Expression_Literal::LiteralTypeCase::kI32:
		return Value::INTEGER(literal.i32());
	case substrait::Expression_Literal::LiteralTypeCase::kI64:
		return Value::BIGINT(literal.i64());
	case substrait::Expression_Literal::LiteralTypeCase::kFp32:
		return Value::FLOAT(literal.fp32());
	case substrait::Expression_Literal::LiteralTypeCase::kFp64:
		return Value::DOUBLE(literal.fp64());
	case substrait::Expression_Literal::LiteralTypeCase::kString:
		return {literal.string()};
	case substrait::Expression_Literal::LiteralTypeCase::kBoolean:
		return Value(literal.boolean());
	default:
		throw NotImplementedException(
		    "Literal type not yet implemented in AST transformer: %s",
		    substrait::Expression_Literal::GetDescriptor()->FindFieldByNumber(literal.literal_type_case())->name());
	}
}

unique_ptr<ParsedExpression> SubstraitToAST::TransformLiteralExpr(const substrait::Expression &sexpr) {
	return make_uniq<ConstantExpression>(TransformLiteralToValue(sexpr.literal()));
}

unique_ptr<ParsedExpression> SubstraitToAST::TransformExpr(const substrait::Expression &sexpr) {
	switch (sexpr.rex_type_case()) {
	case substrait::Expression::RexTypeCase::kLiteral:
		return TransformLiteralExpr(sexpr);
	default:
		throw NotImplementedException(
		    "Expression type not yet implemented in AST transformer: %s",
		    substrait::Expression::GetDescriptor()->FindFieldByNumber(sexpr.rex_type_case())->name());
	}
}

unique_ptr<TableRef> SubstraitToAST::TransformReadOp(const substrait::Rel &sop) {
	auto &sget = sop.read();

	if (sget.has_virtual_table()) {
		// Handle VALUES clause (e.g., SELECT 1)
		if (!sget.virtual_table().values().empty()) {
			auto values_ref = make_uniq<ExpressionListRef>();
			auto literal_values = sget.virtual_table().values();

			// Transform each row of values
			for (auto &row : literal_values) {
				vector<unique_ptr<ParsedExpression>> expr_row;
				for (const auto &value : row.fields()) {
					auto literal_value = TransformLiteralToValue(value);
					expr_row.push_back(make_uniq<ConstantExpression>(literal_value));
				}
				values_ref->values.push_back(std::move(expr_row));
			}

			values_ref->alias = "values";
			return unique_ptr<TableRef>(values_ref.release());
		}
	} else if (sget.has_named_table()) {
		// Handle named tables
		auto base_ref = make_uniq<BaseTableRef>();
		base_ref->schema_name = DEFAULT_SCHEMA;
		base_ref->table_name = sget.named_table().names(0);
		return unique_ptr<TableRef>(base_ref.release());
	}

	throw NotImplementedException("Read operation type not yet supported in AST transformer");
}

unique_ptr<TableRef> SubstraitToAST::TransformRootOp(const substrait::RelRoot &sop) {
	// For now, just transform the input relation
	auto &input = sop.input();

	if (input.rel_type_case() == substrait::Rel::RelTypeCase::kProject) {
		auto &project = input.project();
		auto &project_input = project.input();

		// Get the base table/values
		unique_ptr<TableRef> from_table;
		if (project_input.rel_type_case() == substrait::Rel::RelTypeCase::kRead) {
			from_table = TransformReadOp(project_input);
		} else {
			throw NotImplementedException("Project input type not yet supported");
		}

		// Build SELECT node
		auto select_node = make_uniq<SelectNode>();
		select_node->from_table = std::move(from_table);

		// Add projections
		for (auto &sexpr : project.expressions()) {
			select_node->select_list.push_back(TransformExpr(sexpr));
		}

		// Wrap in SelectStatement and SubqueryRef
		auto select_stmt = make_uniq<SelectStatement>();
		select_stmt->node = std::move(select_node);

		return make_uniq<SubqueryRef>(std::move(select_stmt));
	}

	throw NotImplementedException("Root operation type not yet supported in AST transformer");
}

unique_ptr<TableRef> SubstraitToAST::TransformPlanToTableRef() {
	if (plan.relations().empty()) {
		throw InvalidInputException("Substrait Plan does not have a SELECT statement");
	}

	return TransformRootOp(plan.relations(0).root());
}

} // namespace duckdb
