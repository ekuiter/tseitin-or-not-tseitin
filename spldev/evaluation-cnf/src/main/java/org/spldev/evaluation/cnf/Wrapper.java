package org.spldev.evaluation.cnf;

import java.nio.file.*;
import java.util.*;

import org.spldev.evaluation.process.*;

public class Wrapper extends Algorithm<List<String>> {
	public static final String RESULT_PREFIX = "result: ";

	final Analysis analysis;
	private final ArrayList<String> results = new ArrayList<>();

	public Wrapper(Analysis analysis) {
		this.analysis = analysis;
	}

	public void setTransformation(Analysis transformation) {
		analysis.parameters.transformation = transformation;
	}

	@Override
	protected void addCommandElements() {
		Path tempPath = Paths.get(analysis.parameters.tempPath).resolve("params.dat");
		analysis.write(tempPath);
		addCommandElement("java");
		addCommandElement("-da");
		addCommandElement("-Xmx12g");
		addCommandElement("-cp");
		addCommandElement(System.getProperty("java.class.path"));
		addCommandElement(Runner.class.getCanonicalName());
		addCommandElement(tempPath.toString());
	}

	@Override
	public void postProcess() throws Exception {
		results.clear();
	}

	@Override
	public void readOutput(String line) throws Exception {
		if (line.startsWith(RESULT_PREFIX)) {
			results.add(line.replace(RESULT_PREFIX, "").trim());
		}
	}

	@Override
	public List<String> parseResults() {
		return new ArrayList<>(results);
	}

	@Override
	public String getName() {
		return "Evaluation-CNF";
	}

	@Override
	public String getParameterSettings() {
		return analysis.toString();
	}
}
