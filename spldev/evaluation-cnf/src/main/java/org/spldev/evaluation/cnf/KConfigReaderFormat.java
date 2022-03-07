package org.spldev.evaluation.cnf;

import de.ovgu.featureide.fm.core.PluginID;
import de.ovgu.featureide.fm.core.base.FeatureUtils;
import de.ovgu.featureide.fm.core.base.IFeature;
import de.ovgu.featureide.fm.core.base.IFeatureModel;
import de.ovgu.featureide.fm.core.base.IFeatureStructure;
import de.ovgu.featureide.fm.core.io.AFeatureModelFormat;
import de.ovgu.featureide.fm.core.io.ProblemList;
import org.prop4j.And;
import org.prop4j.Node;
import org.prop4j.NodeReader;

import java.lang.reflect.Field;
import java.util.*;
import java.util.stream.Collectors;

public class KConfigReaderFormat extends AFeatureModelFormat {
	static class KconfigNodeReader extends NodeReader {
		KconfigNodeReader() {
			try {
				Field field = NodeReader.class.getDeclaredField("symbols");
				field.setAccessible(true);
				field.set(this, new String[] { "==", "=>", "|", "&", "!" });
			} catch (NoSuchFieldException | IllegalAccessException e) {
				e.printStackTrace();
			}
		}
	}

	public static final String ID = PluginID.PLUGIN_ID + ".format.fm." + KConfigReaderFormat.class.getSimpleName();

	@Override
	public ProblemList read(IFeatureModel featureModel, CharSequence source) {
		setFactory(featureModel);

		final NodeReader nodeReader = new KconfigNodeReader();
		List<Node> constraints = source.toString().lines() //
			.map(String::trim) //
			.filter(l -> !l.isEmpty()) //
			.filter(l -> !l.startsWith("#")) //
			.map(l -> l.replace("=", "_"))
			.map(l -> l.replace("-", "_"))
			.map(l -> l.replaceAll("def\\((\\w+)\\)", "$1"))
			.map(nodeReader::stringToNode) //
			.filter(Objects::nonNull) // ignore non-Boolean constraints
			.collect(Collectors.toList());

		featureModel.reset();
		And andNode = new And(constraints);
		addNodeToFeatureModel(featureModel, andNode, andNode.getUniqueContainedFeatures());

		return new ProblemList();
	}

	/**
	 * Adds the given propositional node to the given feature model. The current
	 * implementation is naive in that it does not attempt to interpret any
	 * constraint as {@link IFeatureStructure structure}.
	 *
	 * @param featureModel feature model to edit
	 * @param node         propositional node to add
	 * @param variables    the variables of the propositional node
	 */
	private void addNodeToFeatureModel(IFeatureModel featureModel, Node node, Collection<String> variables) {
		// Add a feature for each variable.
		for (final String variable : variables) {
			final IFeature feature = factory.createFeature(featureModel, variable.toString());
			FeatureUtils.addFeature(featureModel, feature);
		}

		// Add a constraint for each conjunctive clause.
		final List<Node> clauses = node instanceof And ? Arrays.asList(node.getChildren())
			: Collections.singletonList(node);
		for (final Node clause : clauses) {
			FeatureUtils.addConstraint(featureModel, factory.createConstraint(featureModel, clause));
		}
	}

	@Override
	public String getSuffix() {
		return "model";
	}

	@Override
	public KConfigReaderFormat getInstance() {
		return this;
	}

	@Override
	public String getId() {
		return ID;
	}

	@Override
	public boolean supportsRead() {
		return true;
	}

	@Override
	public String getName() {
		return "kconfigreader";
	}

}
