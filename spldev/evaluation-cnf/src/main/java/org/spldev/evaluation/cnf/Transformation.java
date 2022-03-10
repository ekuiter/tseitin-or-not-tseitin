package org.spldev.evaluation.cnf;

import de.ovgu.featureide.fm.core.analysis.cnf.CNF;
import de.ovgu.featureide.fm.core.analysis.cnf.formula.FeatureModelFormula;
import de.ovgu.featureide.fm.core.base.IFeatureModel;
import de.ovgu.featureide.fm.core.io.dimacs.DIMACSFormatCNF;
import de.ovgu.featureide.fm.core.io.manager.FeatureModelManager;
import org.sosy_lab.common.ShutdownManager;
import org.sosy_lab.common.configuration.Configuration;
import org.sosy_lab.common.configuration.InvalidConfigurationException;
import org.sosy_lab.common.log.BasicLogManager;
import org.sosy_lab.common.log.LogManager;
import org.sosy_lab.java_smt.SolverContextFactory;
import org.sosy_lab.java_smt.api.*;
import org.spldev.evaluation.util.ModelReader;
import org.spldev.formula.expression.Formula;
import org.spldev.formula.expression.atomic.Atomic;
import org.spldev.formula.expression.atomic.literal.VariableMap;
import org.spldev.formula.expression.io.DIMACSFormat;
import org.spldev.formula.expression.io.FormulaFormatManager;
import org.spldev.formula.expression.transform.Transformer;
import org.spldev.formula.solver.RuntimeTimeoutException;
import org.spldev.formula.solver.javasmt.CNFTseitinTransformer;
import org.spldev.formula.solver.javasmt.FormulaToJavaSmt;
import org.spldev.util.data.Pair;
import org.spldev.util.io.FileHandler;
import org.spldev.util.job.Executor;
import org.spldev.util.logging.Logger;
import org.spldev.util.tree.Trees;
import org.spldev.util.tree.structure.Tree;
import org.spldev.util.tree.visitor.TreeVisitor;

import java.io.*;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;
import java.util.List;
import java.util.concurrent.*;

public abstract class Transformation implements Serializable {
	private static final long serialVersionUID = 1L;
	public static Transformation[] transformations = new Transformation[] {
		new TseitinZ3(),
		new DistributiveFeatureIDE(),
	};

	public Parameters parameters;

	public void setParameters(Parameters parameters) {
		this.parameters = parameters;
		this.parameters.transformation = this;
	}

	static class Result<T> extends Pair<Long, T> {
		public Result(Long key, T value) {
			super(key, value);
		}
	}

	public static Transformation read(Path path) {
		try {
			FileInputStream fileInputStream = new FileInputStream(path.toFile());
			ObjectInputStream objectInputStream = new ObjectInputStream(fileInputStream);
			Transformation transformation = (Transformation) objectInputStream.readObject();
			objectInputStream.close();
			return transformation;
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

	abstract public void run() throws Exception;

	public static class LiteralsCounter implements TreeVisitor<Integer, Tree<?>> {

		private int literals = 0;

		@Override
		public void reset() {
			literals = 0;
		}

		@Override
		public VisitorResult firstVisit(List<Tree<?>> path) {
			if (TreeVisitor.getCurrentNode(path) instanceof Atomic)
				literals++;
			return VisitorResult.Continue;
		}

		@Override
		public Integer getResult() {
			return literals;
		}
	}

	public static class TseitinZ3 extends Transformation {
		private static Configuration config;
		private static LogManager logManager;
		private static SolverContext context;
		private static ShutdownManager shutdownManager;
		private static FormulaManager formulaManager;
		private static BooleanFormulaManager booleanFormulaManager;

		static {
			try {
				config = Configuration.defaultConfiguration();
				logManager = BasicLogManager.create(config);
				shutdownManager = ShutdownManager.create();
				context = SolverContextFactory.createSolverContext(config, logManager, shutdownManager
						.getNotifier(), SolverContextFactory.Solvers.Z3);
				formulaManager = context.getFormulaManager();
				booleanFormulaManager = formulaManager.getBooleanFormulaManager();
			} catch (InvalidConfigurationException e) {
				e.printStackTrace();
			}
		}

		@Override
		public void run() {
			Formula formula = readFormula(Paths.get(parameters.modelPath));
			int variables = VariableMap.fromExpression(formula).size();
			int literals = Trees.traverse(formula, new LiteralsCounter()).get();

			VariableMap variableMap = VariableMap.fromExpression(formula);
			BooleanFormula input = new FormulaToJavaSmt(context,
					variableMap).nodeToFormula(formula);
			try {
				Files.write(Paths.get(getTempPath().toString()+".smt"), formulaManager.dumpFormula(input).toString().getBytes());
			} catch (IOException e) {
				e.printStackTrace();
			}


			Result<Formula> result = executeTransformer(formula, new CNFTseitinTransformer());
			if (result != null) {
				writeFormula(result.getValue(), getTempPath());
				try {
					Files.write(getTempPath(), (
						"c time_transform " + result.getKey() + "\n" +
						"c variables_extract " + variables + "\n" +
						"c literals_extract " + literals + "\n"
					).getBytes(), StandardOpenOption.APPEND);
				} catch (IOException e) {
				}
			}
		}

		@Override
		public String toString() {
			return "z3";
		}
	}

	public static class DistributiveFeatureIDE extends Transformation {
		@Override
		public void run() {
			Formula formula = readFormula(Paths.get(parameters.modelPath));
			int variables = VariableMap.fromExpression(formula).size();
			int literals = Trees.traverse(formula, new LiteralsCounter()).get();
			final IFeatureModel featureModel = FeatureModelManager
					.load(Paths.get(parameters.rootPath).resolve(parameters.modelPath));
			if (featureModel != null) {
				Result<CNF> result = execute(() -> new FeatureModelFormula(featureModel).getCNF());
				if (result != null) {
					de.ovgu.featureide.fm.core.io.manager.FileHandler.save(getTempPath(), result.getValue(),
							new DIMACSFormatCNF());
					try {
					Files.write(getTempPath(), (
						"c time_transform " + result.getKey() + "\n" +
						"c variables_extract " + variables + "\n" +
						"c literals_extract " + literals + "\n"
					).getBytes(), StandardOpenOption.APPEND);
				} catch (IOException e) {
				}
				}
			}
		}

		@Override
		public String toString() {
			return "featureide";
		}
	}
}
