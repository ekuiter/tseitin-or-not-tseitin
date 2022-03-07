package org.spldev.evaluation.cnf;

import de.ovgu.featureide.fm.core.analysis.cnf.CNF;
import de.ovgu.featureide.fm.core.analysis.cnf.formula.FeatureModelFormula;
import de.ovgu.featureide.fm.core.base.IFeatureModel;
import de.ovgu.featureide.fm.core.io.dimacs.DIMACSFormatCNF;
import de.ovgu.featureide.fm.core.io.manager.FeatureModelManager;
import org.spldev.evaluation.util.ModelReader;
import org.spldev.formula.ModelRepresentation;
import org.spldev.formula.expression.Formula;
import org.spldev.formula.expression.atomic.literal.VariableMap;
import org.spldev.formula.expression.io.DIMACSFormat;
import org.spldev.formula.expression.io.FormulaFormatManager;
import org.spldev.formula.expression.transform.Transformer;
import org.spldev.formula.solver.RuntimeTimeoutException;
import org.spldev.formula.solver.javasmt.CNFTseitinTransformer;
import org.spldev.util.data.Pair;
import org.spldev.util.io.FileHandler;
import org.spldev.util.job.Executor;
import org.spldev.util.logging.Logger;

import java.io.*;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.concurrent.*;
import java.util.stream.Collectors;
import java.util.stream.Stream;

public abstract class Analysis implements Serializable {
	private static final long serialVersionUID = 1L;
	public static Analysis[] transformations = new Analysis[] {
		new TseitinZ3(),
		new DistributiveFeatureIDE(),
	};
	public static List<Pair<Class<?>, String[]>> analyses = new ArrayList<>();

	static {
		analyses.add(new Pair<>(Transform.class, new String[] { "TransformTime", "Variables", "Clauses" }));
		// maybe also consider kmax-mined models (to avoid bias by kconfigreader)? but this requires another input mechanism for kmax files
	}

	public Parameters parameters;

	public void setParameters(Parameters parameters) {
		this.parameters = parameters;
	}

	static class Result<T> extends Pair<Long, T> {
		public Result(Long key, T value) {
			super(key, value);
		}
	}

	public static Analysis read(Path path) {
		try {
			FileInputStream fileInputStream = new FileInputStream(path.toFile());
			ObjectInputStream objectInputStream = new ObjectInputStream(fileInputStream);
			Analysis analysis = (Analysis) objectInputStream.readObject();
			objectInputStream.close();
			return analysis;
		} catch (IOException | ClassNotFoundException e) {
			e.printStackTrace();
		}
		return null;
	}

	public void write(Path path) {
		try {
			FileOutputStream fileOutputStream = new FileOutputStream(path.toFile());
			ObjectOutputStream objectOutputStream = new ObjectOutputStream(fileOutputStream);
			objectOutputStream.writeObject(this);
			objectOutputStream.flush();
			objectOutputStream.close();
		} catch (IOException e) {
			e.printStackTrace();
		}
	}

	@Override
	public String toString() {
		return getClass().getSimpleName() + "{" +
			"parameters=" + parameters +
			'}';
	}

	public String[] getResultColumns() {
		return analyses.stream()
			.filter(analysisPair -> analysisPair.getKey().equals(this.getClass()))
			.findFirst().orElseThrow().getValue();
	}

	protected <T> Result execute(Callable<T> method) {
		final ExecutorService executor = Executors.newSingleThreadExecutor();
		final Future<Result> future = executor.submit(() -> {
			T payload = null;
			final long localTime = System.nanoTime();
			try {
				payload = method.call();
			} catch (Exception e) {
				e.printStackTrace();
			}
			final long timeNeeded = System.nanoTime() - localTime;
			return payload == null ? null : new Result(timeNeeded, payload);
		});
		try {
			return future.get(parameters.timeout, TimeUnit.MILLISECONDS);
		} catch (TimeoutException | ExecutionException | InterruptedException | RuntimeTimeoutException e) {
			System.exit(0);
		} finally {
			executor.shutdownNow();
		}
		return null;
	}

	protected Result<Formula> executeTransformer(Formula formula, Transformer transformer) {
		return execute(() -> Executor.run(transformer, formula).orElse(Logger::logProblems));
	}

	protected Formula readFormula(Path path) {
		final ModelReader<Formula> fmReader = new ModelReader<>();
		fmReader.setPathToFiles(Paths.get(parameters.rootPath));
		fmReader.setFormatSupplier(FormulaFormatManager.getInstance());
		return fmReader.read(path.toString()).orElseThrow(p -> new RuntimeException("no feature model"));
	}

	protected void writeFormula(Formula formula, Path path) {
		try {
			FileHandler.save(formula, path, new DIMACSFormat());
		} catch (final IOException e) {
			e.printStackTrace();
		}
	}

	protected Path getTempPath(String suffix) {
		return Paths.get(parameters.tempPath).resolve(
			String.format("%s_%s_%d.%s",
				parameters.system.replaceAll("[/]", "_"),
				parameters.transformation, parameters.iteration, suffix));
	}

	protected Path getTempPath() {
		return getTempPath("dimacs");
	}

	protected boolean fileExists(Path path) {
		try {
			BufferedReader br = new BufferedReader(new FileReader(path.toFile()));
			if (br.readLine() == null)
				return false;
		} catch (IOException e) {
			return false;
		}
		return true;
	}

	protected void printResult(Object o) {
		System.out.println(Wrapper.RESULT_PREFIX + o);
	}

	protected void processFormulaResult(Result<Formula> result) {
		if (result != null) {
			printResult(result.getKey());
			printResult(VariableMap.fromExpression(result.getValue()).size());
			printResult(result.getValue().getChildren().size());
			writeFormula(result.getValue(), getTempPath());
		}
	}

	protected void printResult(Result<?> result) {
		if (result != null) {
			printResult(result.getKey());
			printResult(result.getValue());
		}
	}

	private List<String> getActualFeatures(Stream<String> stream) {
		return stream.filter(name -> name != null && !name.startsWith("__temp__"))
			.filter(name -> !name.startsWith("__Root__"))
			.filter(name -> !name.startsWith("k!"))
			.filter(name -> !name.startsWith("|"))
			.collect(Collectors.toList());
	}

	protected List<String> getActualFeatures(ModelRepresentation rep) {
		return getActualFeatures(rep.getVariables().getNames().stream());
	}

	protected List<String> getActualFeatures(CNF cnf) {
		return getActualFeatures(Arrays.stream(cnf.getVariables().getNames()));
	}

	abstract public void run() throws Exception;

	public static class TseitinZ3 extends Analysis {
		@Override
		public void run() {
			Formula formula = readFormula(Paths.get(parameters.modelPath));
			processFormulaResult(executeTransformer(formula, new CNFTseitinTransformer()));
		}

		@Override
		public String toString() {
			return "z3";
		}
	}

	public static class DistributiveFeatureIDE extends Analysis {
		@Override
		public void run() {
			final IFeatureModel featureModel = FeatureModelManager
					.load(Paths.get(parameters.rootPath).resolve(parameters.modelPath));
			if (featureModel != null) {
				Result<CNF> result = execute(() -> new FeatureModelFormula(featureModel).getCNF());
				if (result != null) {
					printResult(result.getKey());
					printResult(result.getValue().getVariables().size());
					printResult(result.getValue().getClauses().size());
					de.ovgu.featureide.fm.core.io.manager.FileHandler.save(getTempPath(), result.getValue(),
							new DIMACSFormatCNF());
				}
			}
		}

		@Override
		public String toString() {
			return "featureide";
		}
	}

	public static class Transform extends Analysis {
		@Override
		public void run() throws Exception {
			parameters.transformation.run();
		}
	}
}
